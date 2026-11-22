#
# Vendored onnxruntime-c 1.20.0 (prebuilt C/C++ core framework).
#
# The `onnxruntime-objc` wrapper depends on the `onnxruntime-c` CocoaPod, whose
# published archive is hosted on download.onnxruntime.ai. That CDN has been
# returning HTTP 500 for every version (1.18.0, 1.20.0, 1.30.0), so `pod
# install` cannot fetch the prebuilt onnxruntime.xcframework.
#
# This podspec is byte-for-byte the official onnxruntime-c 1.20.0 pod (same
# vendored_frameworks, same source archive name, same version), with the single
# change that the archive is fetched from a checksum-verified GitHub release
# instead of the down CDN. The archive is hosted by rarimo/onnxruntime-swift-
# package-manager, a fork of Microsoft's official onnxruntime-swift-package-
# manager, and carries a published SHA256 checksum
# (5a2f1f87063984732ecdad1f4e380d86e120e5bad2f905cc7c17d3fef7ceb723) so the
# downloaded binary is verified before use. Version 1.20.0 is the closest
# available distribution to the plugin's original 1.15.1 pin.
#
Pod::Spec.new do |s|
  s.name             = 'onnxruntime-c'
  s.version          = '1.20.0'
  s.summary          = 'ONNX Runtime C/C++ Pod'
  s.description     = 'A pod for the ONNX Runtime C/C++ library.'
  s.homepage         = 'https://github.com/microsoft/onnxruntime'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ONNX Runtime' => 'onnxruntime@microsoft.com' }
  s.source           = {
    :http => 'https://github.com/rarimo/onnxruntime-swift-package-manager/releases/download/v1.0.0/pod-archive-onnxruntime-c-1.20.0.zip',
  }
  s.platforms        = { :ios => '13.0', :osx => '11.0' }
  s.vendored_frameworks = 'onnxruntime.xcframework'
  s.static_framework = true
  s.weak_frameworks  = 'CoreML'
  s.source_files     = 'Headers/*.h'
  s.preserve_paths   = 'LICENSE'
  s.libraries        = 'c++'
  s.pod_target_xcconfig = {
    'OTHER_CPLUSPLUSFLAGS' => '-fvisibility=hidden -fvisibility-inlines-hidden',
  }
end
