Pod::Spec.new do |s|
  version = '0.1.0'

  s.name = 'BRBluetoothLib'
  s.version = version
  s.summary = 'Bairong recording card BLE/WiFi iOS SDK.'
  s.description = 'Layered iOS SDK for Bairong recording card BLE, WiFi sync, OTA, FlashIdea, MARK, and earphone mode protocol flows.'
  s.homepage = 'https://github.com/hanyibo520/ble-iOS'
  s.license = { :type => 'Proprietary', :text => 'Copyright 100Credit.' }
  s.author = { '100Credit' => 'ai2c@100credit.cn' }
  s.source = { :git => 'https://github.com/hanyibo520/ble-iOS.git', :tag => "BRBluetoothLib-#{version}" }
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = 'Sources/BRBluetoothLib/**/*.swift'
  s.frameworks = 'Foundation', 'CoreBluetooth', 'CoreLocation', 'Network', 'NetworkExtension', 'SystemConfiguration', 'UIKit'
end
