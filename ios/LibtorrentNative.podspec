Pod::Spec.new do |s|
  s.name             = 'LibtorrentNative'
  s.version          = '0.2.3'
  s.summary          = 'Prebuilt libtorrent XCFramework for iOS'
  s.homepage         = 'https://github.com/tryAGI/LibtorrentSDK'
  s.license          = { :type => 'BSD' }
  s.author           = { 'tryAGI' => 'info@tryagi.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '16.1'
  s.ios.deployment_target = '16.1'

  xcframework_path = 'Frameworks/LibtorrentNative.xcframework'
  xcframework_absolute = File.join(__dir__, xcframework_path)

  if Dir.exist?(xcframework_absolute)
    s.vendored_frameworks = xcframework_path
  end
end
