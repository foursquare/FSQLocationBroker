Pod::Spec.new do |s|
  s.name      = 'FSQLocationBroker'
  s.version   = '1.3.3'
  s.platform  = :ios
  s.summary   = 'A centralized location manager for your app'
  s.homepage  = 'https://github.com/foursquare/FSQLocationBroker'
  s.license   = { :type => 'Apache', :file => 'LICENSE.txt' }
  s.authors   = { 'Brian Dorfman' => 'https://twitter.com/bdorfman',
                  'Cameron Mulhern' => 'http://www.cameronmulhern.com',
                  'Adam Alix' => 'https://twitter.com/adamalix',
                  'Anoop Ranganath' => 'https://twitter.com/anoopr',
                  'Mitchell Livingston' => 'https://twitter.com/livings124',
                  'Eric Bueno' => 'https://twitter.com/sneakybueno' }             
  s.source    = { :git => 'https://github.com/foursquare/FSQLocationBroker.git',
                  :tag => "v#{s.version}" }
  s.source_files  = 'FSQLocationBroker/*.{h,m}'
  s.frameworks    = 'CoreLocation'
  s.requires_arc  = true
end