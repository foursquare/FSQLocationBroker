Pod::Spec.new do |s|
  s.name      = 'FSQLocationBroker'
  s.version   = '1.0.1'
  s.platform  = :ios
  s.summary   = 'A centralized location manager for your app'
  s.homepage  = 'https://github.com/foursquare/FSQLocationBroker'
  s.license   = { :type => 'Apache', :file => 'LICENSE.txt' }
  s.authors   = { 'Adam Alix' => 'https://twitter.com/adamalix',
                  'Anoop Ranganath' => 'https://twitter.com/anoopr',
                  'Brian Dorfman' => 'https://twitter.com/bdorfman' }             
  s.source    = { :git => 'https://github.com/foursquare/FSQLocationBroker.git',
                  :tag => "v#{s.version}" }
  s.source_files  = '*.{h,m}'
  s.frameworks    = 'CoreLocation'
  s.requires_arc  = true
end