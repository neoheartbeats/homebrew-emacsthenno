require_relative "../Library/EmacsBase"
require "digest"

module EmacsPatchHelper
 class << self
   def patches_dir
     @patches_dir ||= File.join(File.expand_path("../..", __FILE__), "patches") 
   end

   def available_patches
     @available_patches ||= Dir[File.join(patches_dir, "*.patch")].map(&:basename)
   end

   def patch_sha256(name)
     Digest::SHA256.file(File.join(patches_dir, name)).hexdigest
   end
 end
end

class Emacsthenno < EmacsBase
 desc "Sthenno's patch of GNU Emacs"
 homepage "https://www.gnu.org/software/emacs/"
 version "31.0.50"
 revision 1

 url "https://github.com/emacs-mirror/emacs.git", branch: "feature/igc"

 BUILD_DEPS = %w[autoconf automake cmake coreutils gcc gnu-sed m4 pkg-config texinfo]
 RUNTIME_DEPS = %w[giflib gnutls jansson librsvg libxml2 webp libgccjit tree-sitter libmps]
 BUILD_ONLY_DEPS = %w[gmp libjpeg zlib]

 BUILD_DEPS.each { |dep| depends_on dep => :build }
 RUNTIME_DEPS.each { |dep| depends_on dep }
 BUILD_ONLY_DEPS.each { |dep| depends_on dep => :build }

 EmacsPatchHelper.available_patches.each do |patch_name|
   resource patch_name do
     url "https://raw.githubusercontent.com/neoheartbeats/homebrew-emacsthenno/main/patches/#{patch_name}"
     sha256 EmacsPatchHelper.patch_sha256(patch_name)
   end
 end

 def install
   args = common_args + %w[
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

   setup_build_environment
   apply_patches
   build_emacs(args)
   finalize_installation
 end

 def post_install
   Dir.glob(info/"emacs"/"*.info") do |info_file|
     system "install-info", "--info-dir=#{info}/emacs", info_file
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

 private

 def common_args
   %W[
     --enable-locallisppath=#{HOMEBREW_PREFIX}/share/emacs/site-lisp
     --infodir=#{info}/emacs
     --prefix=#{prefix}
   ]
 end

 def setup_build_environment
   gcc = Formula["gcc"].any_installed_version
   gcc_lib = "#{HOMEBREW_PREFIX}/lib/gcc/#{gcc.major}"
   
   ENV.append "LDFLAGS", [
     "-L#{gcc_lib}",
     "-I#{Formula["gcc"].include}",
     "-I#{Formula["libgccjit"].include}", 
     "-I#{Formula["gmp"].include}",
     "-I#{Formula["libjpeg"].include}"
   ].join(" ")
   
   ENV.append_to_cflags "-O2 -march=native -pipe -DFD_SETSIZE=10000 -DDARWIN_UNLIMITED_SELECT"
   %w[coreutils gnu-sed].each { |f| ENV.prepend_path "PATH", Formula[f].opt_libexec/"gnubin" }
 end

 def apply_patches
   resources.select { |r| r.name.end_with?(".patch") }.each do |r|
     r.stage do
       ohai "Applying patch: #{r.name}"
       system "patch", "-p1", "-i", Pathname.pwd/r.name, "-d", buildpath
     end
   end
 end

 def build_emacs(args)
   system "./autogen.sh"
   system "./configure", *args
   system "make", "clean"
   system "make", "NATIVE_FULL_AOT=1", "BYTE_COMPILE_EXTRA_FLAGS=--eval '(setq comp-speed 2)'"
   system "make", "install"
 end

 def finalize_installation
   prefix.install Dir["nextstep/Emacs.app"]
   (prefix/"Emacs.app/Contents").install "native-lisp" if File.directory?("native-lisp")
   remove_conflicting_files
   create_wrapper_script
 end

 def remove_conflicting_files
   %w[bin/ctags man1/ctags.1.gz].each do |f|
     path = prefix/f
     path.unlink if path.exist?
   end
 end

 def create_wrapper_script
   bin/"emacs".unlink if bin/"emacs".exist?
   (bin/"emacs").write <<~EOS
     #!/bin/bash
     exec "#{prefix}/Emacs.app/Contents/MacOS/Emacs" "$@"
   EOS
   (bin/"emacs").chmod 0755
 end
end