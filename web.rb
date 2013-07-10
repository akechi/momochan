# coding: utf-8
require 'bundler'
require 'digest/sha1'
require 'json'
require 'igo-ruby'

Dir.chdir File.dirname(__FILE__)
Bundler.require
set :environment, :production

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/momochan.db")
class Momochan
  include DataMapper::Resource
  property :id, Serial
  property :text, String, :length => 4096
  property :created_at, DateTime
end
DataMapper.finalize
Momochan.auto_upgrade!

class Splitter
  def initialize()
    @tagger = Igo::Tagger.new('ipadic')
  end
  def split(str)
    ['__BEGIN__', *@tagger.wakati(str), '__END__']
  end
end

class Markov
  def initialize()
    @table = []
  end
  def study(words)
    words.each_cons(3) do |a, b, c|
      @table << [a, b, c]
    end
  end
  def search1(key)
    @table.
      select {|a, b, c| a == key }.
      map {|a, b, c| b }.
      sample
  end
  def search2(key1, key2)
    @table.
      select {|a, b, c| a == key1 && b == key2 }.
      map {|a, b, c| c }.
      sample
  end
  def build
    array = []
    key1 = '__BEGIN__'
    key2 = search1(key1)
    return [] unless key2
    until key2 == '__END__'
      array << key2
      key1, key2 = key2, search2(key1, key2)
    end
    array
  end
end

$markov = Markov.new
$splitter = Splitter.new

Momochan.all.each do |m|
  puts m['text']
  $markov.study($splitter.split(m['text']))
end

def momochan
  result = ''
  11.times do
    result = $markov.build.join('')
    break if result.size < 140 && result !~ /^https?:\/\/\S+$/
  end
  result.gsub(/[“”「」『』【】]/, '')
end

post '/lingr/' do
  json = JSON.parse(request.body.string)
  json["events"].map {|e| e['message'] }.compact.map {|message|
    text = message['text']
    if /#momochan$/ =~ text
      momochan
    else
      Momochan.create({:text => text}).update
      $markov.study($splitter.split(text))
      ""
    end
  }.join.rstrip[0..999]
end

get '/' do
  momochan
end
