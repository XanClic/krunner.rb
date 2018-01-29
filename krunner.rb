#!/usr/bin/ruby

require 'dbus'
require 'json'

def find_krunner_interfaces(node)
    if node.object && node.object['org.kde.krunner1']
        return [node.object]
    end

    ret = []
    node.values.each do |value|
        ret += find_krunner_interfaces(value)
    end
    return ret
end

def update_service_list(dbus)
    list = {}

    puts 'Updating service list...'

    names = dbus.proxy.ListNames[0].reject { |name| name[0] == ':' }
    services = names.select.with_index { |name, i|
        print "\r#{i + 1}/#{names.length}"
        $stdout.flush

        begin
            service = dbus[name]
            service.introspect
            objs = find_krunner_interfaces(service.root)
            if !objs.empty?
                list[name] = objs.map { |obj| obj.path }
            end
        rescue Interrupt
            puts
            exit 0
        rescue
        end
    }

    puts
    puts "Found #{list.length} KRunner service#{list.length == 1 ? '' : 's'}"
    puts

    IO.write('services.json', JSON.generate(list))

    return list
end

dbus = DBus.session_bus

args = ARGV.to_a
if args[0] == '--refresh-services'
    args.shift
    update_service_list(dbus)
end

services = {}
begin
    services = JSON.parse(IO.read('services.json'))
rescue
    services = update_service_list(dbus)
end

service_handles = {}
services.each do |name, objs|
    service = dbus[name]
    service.introspect

    objs.each do |obj|
        service_handles[[name, obj]] =
            { service: service,
              object: service.object(obj)['org.kde.krunner1'] }
    end
end

matches = []
service_handles.each do |id, handles|
    matches += handles[:object].Match(args.join(' '))[0].map { |result|
        { id: id,
          action: result[0],
          description: result[1],
          icon: result[2],
          match_category: result[3],
          relevance: result[4],
          more: result[5] }
    }
end

matches.sort! do |x, y|
    [x[:relevance], x[:description]] <=> [y[:relevance], y[:description]]
end


if matches.empty?
    puts 'No results.'
    exit 0
end


matches.each_with_index do |match, i|
    puts "[#{i}] #{match[:id][0]}#{match[:id][1]}: #{match[:description]}"
end

print '> '
$stdout.flush

index = Integer($stdin.readline.strip)

if index < 0 || index >= matches.length
    $stderr.puts 'Invalid index'
    exit 1
end

service_handles[matches[index][:id]][:object].Run(matches[index][:action], '')
