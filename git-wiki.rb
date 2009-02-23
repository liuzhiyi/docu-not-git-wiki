#!/usr/bin/ruby

require 'rubygems'
require 'sinatra'
require 'grit'
require 'rdiscount'

module GitWiki
  class << self
    attr_accessor :root_page, :extension, :link_pattern
    attr_reader :wiki_name, :repository
  end
  @wiki_name = File.basename(File.expand_path(ARGV[0] || '~/wiki'))
  @repository = Grit::Repo.new(File.expand_path(ARGV[0] || '~/wiki'))
  @extension = ARGV[1] || '.markdown'
  @root_page = ARGV[2] || 'index'
  @link_pattern = /\[\[(.*?)\]\]/
end

class Page
  def self.find_all
    GitWiki.repository.tree.contents.collect {|blob| new(blob) }
  end

  def self.find_or_create(name)
    path = name + GitWiki.extension
    blob = GitWiki.repository.tree/path
    new(blob || Grit::Blob.create(GitWiki.repository, :name => path))
  end

  def self.wikify(content)
    content.gsub(GitWiki.link_pattern) {|match| link($1) }
  end

  def self.link(text)
    page = find_or_create(text.gsub(/[^\w\s]/, '').split.join('-').downcase)
    "<a class='page #{page.css_class}' href='#{page.url}'>#{text}</a>"
  end

  def initialize(blob)
    @blob = blob
  end

  def to_s
    @blob.name.sub(/#{GitWiki.extension}$/, '')
  end

  def url
    to_s == GitWiki.root_page ? '/' : "/pages/#{to_s}"
  end

  def edit_url
    "/pages/#{to_s}/edit"
  end

  def css_class
    @blob.id ? 'existing' : 'new'
  end

  def content
    @blob.data
  end

  def to_html
    Page.wikify(RDiscount.new(content).to_html)
  end

  def save!(data)
    Dir.chdir(GitWiki.repository.working_dir) do
      File.open(@blob.name, 'w') {|f| f.puts(data.gsub("\r\n", "\n")) }
      GitWiki.repository.add(@blob.name)
      GitWiki.repository.commit_index("web commit: #{self}")
    end
  end
end

get '/' do
  @page = Page.find_or_create(GitWiki.root_page)
  haml :show
end

get '/pages/' do
  @pages = Page.find_all
  haml :list
end

get '/pages/:page/?' do
  @page = Page.find_or_create(params[:page])
  haml :show
end

get '/pages/:page/edit' do
  @page = Page.find_or_create(params[:page])
  haml :edit
end

post '/pages/:page/edit' do
  @page = Page.find_or_create(params[:page])
  @page.save!(params[:body])
  redirect @page.url
end
