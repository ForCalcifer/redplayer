platform :ios, '16.0'
use_frameworks!

target 'LocalPlayer' do
  # 官方 VideoLAN MobileVLCKit：全格式解码（MKV/AVI/FLV/TS/WebM/MP4/MOV/RMVB...）
  pod 'MobileVLCKit', '~> 3.7'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      # Xcode 15 默认沙盒化脚本，会阻止 CocoaPods 的 copy resources 脚本
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end
