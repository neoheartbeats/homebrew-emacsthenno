# Formula/emacsthenno.rb

require_relative "../Library/EmacsBase"

class EmacSthenno < EmacsBase
  desc "Sthenno's patch of GNU Emacs"
  homepage "https://www.gnu.org/software/emacs/"
  version "31.0.50"
  revision 1

  url "https://github.com/emacs-mirror/emacs.git", :branch => "scratch/igc"

  depends_on "autoconf"   => :build
  depends_on "coreutils"  => :build
  depends_on "gnu-sed"    => :build
  depends_on "texinfo"    => :build
  depends_on "automake"   => :build
  depends_on "cmake"      => :build
  depends_on "pkg-config" => :build
  depends_on "gcc"        => :build
  depends_on "m4"         => :build
  
  depends_on "giflib"
  depends_on "gnutls"
  depends_on "librsvg"
  depends_on "libxml2"
  depends_on "jansson"
  depends_on "webp"
  
  depends_on "gmp"       => :build
  depends_on "libjpeg"   => :build
  depends_on "zlib"      => :build
  depends_on "libgccjit"
  
  depends_on "tree-sitter"
  depends_on "libmps"

  def patches_path
    @patches_path ||= File.expand_path("../../patches", __FILE__)
  end

  def patch_sha256(name)
    require "digest"
    Digest::SHA256.file(File.join(patches_path, name)).hexdigest
  end

  Dir[File.join(patches_path, "*.patch")].sort.each do |patch_file|
    patch_name = File.basename(patch_file)
    resource patch_name do
      url "https://raw.githubusercontent.com/neoheartbeats/homebrew-emacsthenno/main/patches/#{patch_name}"
      sha256 patch_sha256(patch_name)
    end
  end


  def install
    args = %W[
      --enable-locallisppath=#{HOMEBREW_PREFIX}/share/emacs/site-lisp
      --infodir=#{info}/emacs
      --prefix=#{prefix}
      --with-ns
      --disable-ns-self-contained
      --with-native-compilation
      --with-tree-sitter
      --with-xwidgets
      --with-mps
      --with-modules
      --with-gnutls
      --with-rsvg
      --with-xml2
      --with-webp
      --with-poll
    ]

    make_flags = []

    gcc_version = Formula["gcc"].any_installed_version
    gcc_version_major = gcc_version.major
    gcc_lib = "#{HOMEBREW_PREFIX}/lib/gcc/#{gcc_version_major}"

    ENV.append "CFLAGS", "-I#{Formula["gcc"].include}"
    ENV.append "CFLAGS", "-I#{Formula["libgccjit"].include}"

    ENV.append "LDFLAGS", "-L#{gcc_lib}"
    ENV.append "LDFLAGS", "-I#{Formula["gcc"].include}"
    ENV.append "LDFLAGS", "-I#{Formula["libgccjit"].include}"
    ENV.append "LDFLAGS", "-I#{Formula["gmp"].include}"
    ENV.append "LDFLAGS", "-I#{Formula["libjpeg"].include}"

    make_flags << "NATIVE_FULL_AOT=1"
    make_flags << "BYTE_COMPILE_EXTRA_FLAGS=--eval '(setq comp-speed 2)'"

    ENV.append "CFLAGS", "-O2 -march=native -pipe -DFD_SETSIZE=10000 -DDARWIN_UNLIMITED_SELECT"

    ENV.prepend_path "PATH", Formula["coreutils"].opt_libexec/"gnubin"
    ENV.prepend_path "PATH", Formula["gnu-sed"].opt_libexec/"gnubin"

    system "./autogen.sh"

    resources.each do |r|
      r.stage do
        ohai "Applying patch: #{r.name}"
        system "patch", "-p1", "-i", Pathname.pwd/r.name, "-d", buildpath
      end
    end

    system "./configure", *args

    system "make", *make_flags
    system "make", "install"

    prefix.install "nextstep/Emacs.app"
    prefix.install_metafiles

    (prefix/"Emacs.app/Contents").install "native-lisp"

    (bin/"emacs").write <<~EOS
      #!/bin/bash
      exec #{prefix}/Emacs.app/Contents/MacOS/Emacs "$@"
    EOS
  end

  def caveats
    <<~EOS
      Emacs.app was installed to:
        #{prefix}
      To link the Application:
        ln -s #{prefix}/Emacs.app /Applications
    EOS
  end

  service do
    run [opt_bin/"emacs", "--fg-daemon"]
    keep_alive true
    log_path "/tmp/homebrew.mxcl.emacs-thenno.stdout.log"
    error_log_path "/tmp/homebrew.mxcl.emacs-thenno.stderr.log"
  end

  test do
    assert_equal "4", shell_output("#{bin}/emacs --batch --eval=\"(print (+ 2 2))\"").strip
  end
end