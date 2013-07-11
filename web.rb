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
    @table = {}
  end
  def study(words)
    words.each_cons(3) do |a, b, c|
      @table[a] ||= []
      @table[a] << [b, c]
    end
  end
  def search1(key)
    @table[key].
      map {|(b, c)| b }.
      sample
  end
  def search2(key1, key2)
    @table[key1].
      select {|(b, c)| b == key2 }.
      map {|(b, c)| c }.
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

module App
  module_function
  def momochan(markov, text)
    tokens = @splitter.split(text)
    markov.study(tokens)
    text = 21.times.inject('') {|_, _|
      result = markov.build.join('')
      if tokens[1...-1].select {|x| x.size >= 2 && result[x] }.empty?
        result
      elsif result.size < 140 && /^https?:\/\/\S+$/ !~ result
        break result
      else
        result
      end
    }
    text.gsub(/[“”「」『』【】"]/, '')
  end

  def momochan_info
    {
      size: Momochan.all.size,
      started_at: @t0,
      boot_time: @t1 - @t0,
      ready_p: @ready_p
    }.to_json
  end

  @t0 = Time.now
  @t1 = @t0
  @ready_p = false

  @markov = Markov.new
  @splitter = Splitter.new
  class << self
    attr_reader :markov
    attr_reader :splitter
  end

  Thread.start do
    Momochan.all.each do |m|
      #puts m['text']
      @markov.study(@splitter.split(m['text']))
    end
    @ready_p = true
    @t1 = Time.now
  end
end

post '/lingr/' do
  json = JSON.parse(request.body.string)
  json["events"].map {|e| e['message'] }.compact.map {|message|
    text = message['text']
    next App.momochan_info if /^#momochan info$/ =~ text
    regexp = /#m[aiueo]*m[aiueo]*ch?[aiueo]*n|#amachan/
    mcs = text.scan(regexp).map {|_|
      App.momochan(App.markov, text.gsub(regexp, ''))
    }
    mgs = text.scan(/#momonga/).map {|_|
      [*["はい"]*10, "うるさい"].sample
    }
    reply = [mcs + mgs].join("\n")
    if reply.empty?
      Momochan.create({:text => text}).update
      App.markov.study(App.splitter.split(text))
      ""
    else
      reply
    end
  }.join.rstrip[0..999]
end

get '/' do
  App.momochan(App.markov, '')
end

get '/dev' do
  App.momochan_info
end
