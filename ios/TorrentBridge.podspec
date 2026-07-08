Pod::Spec.new do |s|
  s.name             = 'TorrentBridge'
  s.version          = '0.1.0'
  s.summary          = 'Native iOS torrent bridge'
  s.homepage         = 'https://github.com/rakibshorkar2/ios3'
  s.license          = { :type => 'BSD' }
  s.author           = { 'rakibshorkar2' => 'rakib@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '16.1'
  s.ios.deployment_target = '16.1'
  s.source_files     = 'Runner/TorrentService.swift', 'Runner/TorrentManager.swift', 'Runner/TorrentCppWrapper.mm', 'Runner/TorrentCppWrapper.h', 'Runner/LibtorrentNative.h'
  s.public_header_files = 'Runner/TorrentCppWrapper.h'
  s.dependency 'Flutter'
  s.dependency 'LibtorrentNative'
end
