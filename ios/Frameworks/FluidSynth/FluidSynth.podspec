Pod::Spec.new do |s|
  s.name             = 'FluidSynth'
  s.version          = '2.6.0'
  s.summary          = 'FluidSynth soundfont synthesizer library'
  s.homepage         = 'https://www.fluidsynth.org'
  s.license          = { :type => 'LGPL' }
  s.author           = 'FluidSynth Team'
  s.source           = { :path => '.' }
  s.ios.deployment_target = '13.0'
  s.vendored_frameworks = 'FluidSynth.xcframework'
  s.libraries        = 'c++'
  s.frameworks       = 'AudioToolbox', 'CoreAudio', 'CoreMIDI'
end
