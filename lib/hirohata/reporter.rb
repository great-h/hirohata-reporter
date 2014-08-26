require "hirohata/reporter/version"
require 'yaml'
require 'rss'
require 'date'
require 'active_support/all'
require 'rails-html-sanitizer'

module Hirohata
  class Reporter
    def self.config
      YAML.load_file(File.join(File.dirname(__FILE__),"..","..","config.yml"))
    end

    def self.report
      reporter = Hirohata::Reporter.new(config)
      reporter.report(Date.today.last_week, ARGV.first || :all)
    end

    def initialize(config)
      @projects =  config["targets"].map do |project|
        Hirohata::Project.new(project)
      end
    end

    def report(date = Date.today,target = :all)
      start = date.beginning_of_week
      end_date = date.next_week.beginning_of_week.yesterday
      range = start...end_date
      ret = "#{start} 〜 #{end_date}\n\n"
      case target
      when :all
        targets = @projects
      when String
        targets = @projects.delete_if { |project| project.name != target}
      end
      reports = targets.map { |project| project.report(range) }
      unless reports.empty?
        ret += reports.join("\n\n")
      end
    end
  end

  class Project
    def initialize(config)
      @config = config
    end

    def name
      @config["name"]
    end

    def sources
      @config["sources"].map { |source| Source.new(source,self) }
    end

    def report(range)
      reports = sources.map { |source| source.report(range) }.flatten
      if reports.empty?
        ""
      else
        ret = "# " + name
        ret += "\n\n"
        ret += reports.join
        ret
      end
    end
  end

  class Source
    attr_reader :project

    def initialize(config,project)
      @config = config
      @project = project
    end

    def url
      @config["url"]
    end

    def type
      @config["type"]
    end

    def week_items(range)
      case type
      when "rss"
        parse_rss(range)
      when "facebook"
        parse_facebook(range)
      else
        raise 'unknow source type'
      end
    end

    def parse_rss(range)
      parse_rss_base(range) do |item|
        title = item.title
        link = item.link
        date = item.date.to_date
        "#{date} [#{title}](#{link})"
      end
    end

    def parse_facebook(range)
      parse_rss_base(range) do |item|
        full_sanitizer = Rails::Html::FullSanitizer.new
        title = full_sanitizer.sanitize(item.description)[0..100]
        link = item.link
        date = item.date.to_date
        "#{date} [#{title}](#{link})"
      end
    end

    def parse_rss_base(range)
      begin
        rss = RSS::Parser.parse(url,false)
      rescue
        $stderr.puts "parse error: #{project.name} url: #{url} type: #{type}"
        raise
      end

      rss.items.delete_if { |item|
        ! range.include? item.date.to_date
      }.map { |item|
        yield item
      }
    end

    def report(range)
      week_items(range).map { |item| "* #{item}\n" }
    end
  end
end
