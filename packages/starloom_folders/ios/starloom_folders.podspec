Pod::Spec.new do |s|
  s.name             = 'starloom_folders'
  s.version          = '0.1.0'
  s.summary          = 'Folder picker with persistent bookmarks for Starloom.'
  s.description      = 'Lets Starloom read music from a folder picked in Files.'
  s.homepage         = 'https://github.com/FTSFrosTy/Starloom'
  s.license          = { :type => 'Private' }
  s.author           = { 'Starloom' => 'none@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'starloom_folders/Sources/starloom_folders/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
