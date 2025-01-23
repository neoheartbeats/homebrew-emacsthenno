# Formula/emacsthenno.rb

require_relative "../Library/EmacsBase"
require "digest"

module EmacsPatchHelper
  def self.formula_dir
    File.expand_path("../..", __FILE__)
  end

  def self.patches_dir
    File.join(formula_dir, "patches")
  end

  def self.patch_sha256(name)
    Digest::SHA256.file(File.join(patches_dir, name)).hexdigest
  end

  def self.available_patches
    Dir[File.join(patches_dir, "*.patch")].map { |f| File.basename(f) }
  end
end

class Emacsthenno < EmacsBase
  desc "Sthenno's patch of GNU Emacs"
  homepage "https://www.gnu.org/software/emacs/"
  version "31.0.50"
  revision 1

  url "https://github.com/emacs-mirror/emacs.git", branch: "feature/igc"

  # Build dependencies
  depends_on "autoconf"   => :build
  depends_on "automake"   => :build
  depends_on "cmake"      => :build
  depends_on "coreutils"  => :build
  depends_on "gcc"        => :build
  depends_on "gnu-sed"    => :build
  depends_on "m4"         => :build
  depends_on "pkg-config" => :build
  depends_on "texinfo"    => :build

  # Runtime dependencies
  depends_on "giflib"
  depends_on "gnutls"
  depends_on "jansson"
  depends_on "librsvg"
  depends_on "libxml2"
  depends_on "webp"
  depends_on "libgccjit"
  depends_on "tree-sitter"
  depends_on "libmps"
  depends_on "gmp"       => :build
  depends_on "libjpeg"   => :build
  depends_on "zlib"      => :build

  # Dynamically create resource blocks for each *.patch in patches dir
  EmacsPatchHelper.available_patches.each do |patch_name|
    resource patch_name do
      url "https://raw.githubusercontent.com/neoheartbeats/homebrew-emacsthenno/main/patches/#{patch_name}"
      sha256 EmacsPatchHelper.patch_sha256(patch_name)
    end
  end

  def install
    # Configure arguments
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
    ]

    # Set up environment and flags
    gcc_version = Formula["gcc"].any_installed_version
    gcc_lib     = "#{HOMEBREW_PREFIX}/lib/gcc/#{gcc_version.major}"

    ENV.append "LDFLAGS", "-L#{gcc_lib}"
    ENV.append "LDFLAGS", "-I#{Formula["gcc"].include}"
    ENV.append "LDFLAGS", "-I#{Formula["libgccjit"].include}"
    ENV.append "LDFLAGS", "-I#{Formula["gmp"].include}"
    ENV.append "LDFLAGS", "-I#{Formula["libjpeg"].include}"

    ENV.append_to_cflags "-O2 -march=native -pipe -DFD_SETSIZE=10000 -DDARWIN_UNLIMITED_SELECT"

    ENV.prepend_path "PATH", Formula["coreutils"].opt_libexec/"gnubin"
    ENV.prepend_path "PATH", Formula["gnu-sed"].opt_libexec/"gnubin"

    # Run autogen (necessary for Emacs builds from git)
    system "./autogen.sh"

    # Apply all patch resources that end with `.patch`
    resources.each do |r|
      next unless r.name.end_with?(".patch")
      r.stage do
        ohai "Applying patch: #{r.name}"
        system "patch", "-p1", "-i", Pathname.pwd/r.name, "-d", buildpath
      end
    end

    # Configure and build
    system "./configure", *args
    system "make", "clean"

    make_flags = [
      "NATIVE_FULL_AOT=1",
      "BYTE_COMPILE_EXTRA_FLAGS=--eval '(setq comp-speed 2)'"
    ]
    system "make", *make_flags
    system "make", "install"

    # Install Emacs.app in prefix
    prefix.install Dir["nextstep/Emacs.app"]
    (prefix/"Emacs.app/Contents").install "native-lisp" if File.directory?("native-lisp")

    # Remove ctags conflicts
    (bin/"ctags").unlink if (bin/"ctags").exist?
    (man1/"ctags.1.gz").unlink if (man1/"ctags.1.gz").exist?

    # Wrapper script for CLI
    (bin/"emacs").unlink if File.exist?(bin/"emacs")
    (bin/"emacs").write <<~EOS
      #!/bin/bash
      exec "#{prefix}/Emacs.app/Contents/MacOS/Emacs" "$@"
    EOS
  end

  def post_install
    emacs_info_dir = info/"emacs"
    Dir.glob(emacs_info_dir/"*.info") do |info_file|
      system "install-info", "--info-dir=#{emacs_info_dir}", info_file
    end
  end

  def caveats
    <<~EOS
      Emacs.app was installed to:
        #{prefix}
      To link the Application in /Applications (optional):
        ln -s #{prefix}/Emacs.app /Applications
    EOS
  end

  service do
    run [opt_bin/"emacs", "--fg-daemon"]
    keep_alive true
    log_path "/tmp/homebrew.mxcl.emacsthenno.stdout.log"
    error_log_path "/tmp/homebrew.mxcl.emacsthenno.stderr.log"
  end

  test do
    assert_equal "4", shell_output("#{bin}/emacs --batch --eval='(print (+ 2 2))'").strip
  end
end