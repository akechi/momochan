# -*- coding: utf-8 -*-
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
    array = Array.new
    array << '__BEGIN__'
    array += @tagger.wakati(str)
    array << '__END__'
    array
  end
end

class Markov
  def initialize()
    @table = Array.new
  end
  def study(words)
    return if words.size < 3
    for i in 0..(words.size - 3) do
      @table << [words[i], words[i + 1], words[i + 2]]
    end
  end
  def search1(key)
    array = Array.new
    @table.each {|row|
      array << row[1] if row[0] == key
    }
    array.sample
  end
  def search2(key1, key2)
    array = Array.new
    @table.each {|row|
      array << row[2] if row[0] == key1 && row[1] == key2
    }
    array.sample
  end
  def build
    array = Array.new
    key1 = '__BEGIN__'
    key2 = search1(key1)
    return [] unless key2
    while key2 != '__END__'
      array << key2
      key3 = search2(key1, key2)
      key1 = key2
      key2 = key3
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
  counter = 0
  while counter <= 10
    result = $markov.build.join('')
    break if result.size < 140
    counter += 1
  end
  result
end

post '/lingr/' do
  json = JSON.parse(request.body.string)
  json["events"].map {|e| e['message'] }.compact.map {|message|
    text = message['text']
    if text == '#momochan'
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
