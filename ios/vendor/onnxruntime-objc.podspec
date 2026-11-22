#
# Vendored onnxruntime-objc 1.20.0 (Objective-C wrapper).
#
# The onnxruntime Flutter plugin (^1.4.1) depends on the `onnxruntime-objc`
# CocoaPod. Its published archive is hosted on download.onnxruntime.ai, which
# has been returning HTTP 500 for every version, so `pod install` cannot
# fetch it. This podspec vendors the wrapper's Objective-C source (Microsoft's
# official MIT-licensed onnxruntime Objective-C API, version 1.20.0) directly
# into the repository, so the wrapper no longer depends on the broken CDN.
#
# The wrapper is pure source; only the `onnxruntime-c` core framework (a
# prebuilt binary) still needs a distribution, and that comes from a
# checksum-verified GitHub release (see onnxruntime-c.podspec). Version 1.20.0
# is the closest available distribution to the plugin's original 1.15.1 pin
# and is API-compatible with the onnxruntime C API the plugin calls.
#
Pod::Spec.new do |s|
  s.name             = 'onnxruntime-objc'
  s.version          = '1.20.0'
  s.summary          = 'ONNX Runtime Objective-C Pod'
  s.description     = <<-DESC
A pod for the ONNX Runtime Objective-C API.
                       DESC
  s.homepage         = 'https://github.com/microsoft/onnxruntime'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ONNX Runtime' => 'onnxruntime@microsoft.com' }
  s.source           = { :path => '.' }
  s.platforms        = { :ios => '13.0', :osx => '11.0' }
  s.preserve_paths   = 'LICENSE'
  s.default_subspecs = 'Core'
  s.static_framework = true

  s.subspec 'Core' do |core|
    core.dependency 'onnxruntime-c', '1.20.0'
    core.requires_arc = true
    core.compiler_flags = [
      '-std=c++17',
      '-fobjc-arc-exceptions',
      '-Wall',
      '-Wextra',
      '-Werror',
    ]
    core.pod_target_xcconfig = {
      'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/objectivec"',
      'OTHER_CPLUSPLUSFLAGS' => '-fvisibility=hidden -fvisibility-inlines-hidden',
    }
    core.public_header_files = [
      'objectivec/include/ort_coreml_execution_provider.h',
      'objectivec/include/ort_custom_op_registration.h',
      'objectivec/include/ort_session.h',
      'objectivec/include/ort_env.h',
      'objectivec/include/onnxruntime.h',
      'objectivec/include/ort_enums.h',
      'objectivec/include/ort_value.h',
      'objectivec/include/ort_xnnpack_execution_provider.h',
    ]
    core.source_files = [
      'objectivec/include/ort_env.h',
      'objectivec/error_utils.mm',
      'objectivec/ort_session.mm',
      'objectivec/include/ort_custom_op_registration.h',
      'objectivec/include/ort_session.h',
      'objectivec/ort_coreml_execution_provider.mm',
      'objectivec/ort_env.mm',
      'objectivec/cxx_utils.mm',
      'objectivec/ort_env_internal.h',
      'objectivec/include/ort_xnnpack_execution_provider.h',
      'objectivec/include/ort_coreml_execution_provider.h',
      'objectivec/ort_enums_internal.h',
      'objectivec/ort_value_internal.h',
      'objectivec/include/onnxruntime.h',
      'objectivec/cxx_utils.h',
      'objectivec/include/ort_enums.h',
      'objectivec/ort_session_internal.h',
      'objectivec/assert_arc_enabled.mm',
      'objectivec/cxx_api.h',
      'objectivec/ort_xnnpack_execution_provider.mm',
      'objectivec/ort_value.mm',
      'objectivec/error_utils.h',
      'objectivec/ort_enums.mm',
      'objectivec/include/ort_value.h',
    ]
  end
end
