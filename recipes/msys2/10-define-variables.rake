self.sandboxdir = "#{thisdir}/#{package.msysdir}"
self.msys2_base_tar_url = "http://repo.msys2.org/distrib/msys2-#{package.msys_arch}-latest.tar.xz"
self.msys2_base_tar_file = File.join(thisdir, File.basename(self.msys2_base_tar_url))
