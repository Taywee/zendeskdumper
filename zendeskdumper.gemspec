require_relative 'lib/zendeskdumper/meta'

Gem::Specification.new do |s|
  # Loop through constants and set the relevant attribute on the gem
  # specification object
  ZenDeskDumper::Meta.constants(false).each do |sym|
    name = sym.to_s.downcase
    value = ZenDeskDumper::Meta.const_get(sym)
    s.send("#{name}=", value)
  end
end
