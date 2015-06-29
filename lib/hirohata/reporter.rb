# -*- coding: utf-8 -*-
require "hirohata/reporter/version"
require 'yaml'
require 'rss'
require 'date'
require 'fbgraph'
FBGraph.config # Rails HTML SanitizerのせいでRailsプロジェクトと冠ちがいしてしまうので対策
require 'active_support/all'
require 'rails-html-sanitizer'

module Hirohata
  class Reporter
    def self.config
      YAML.load_file(File.join(File.dirname(__FILE__),"..","..","config.yml"))
    end

    def self.report
      reporter = Hirohata::Reporter.new(config)
      reporter.report(Date.today.last_week, :all)
    end

    def self.start_date(date)
      date.beginning_of_week
    end

    def self.end_date(date)
      date.next_week.beginning_of_week.yesterday
    end

    def initialize(config)
      @projects =  config["targets"].map do |project|
        Hirohata::Project.new(project)
      end
    end

    def report(date = Date.today,target = :all)
      start = self.class.start_date(date)
      end_date = self.class.end_date(date)
      range = start..end_date
      ret = <<STRING
---
layout: post
title:  "#{end_date.strftime('%Y年%m月%d日')}までの各ユニットの活動"
date:   #{end_date} 00:00:00
---

STRING

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
      ret
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

    def url
      @config["url"]
    end

    def report(range)
      reports = sources.map { |source| source.report(range) }.flatten
      if reports.empty?
        ""
      else
        ret = "# [#{name}](#{url})"
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

    def client
      @client||= FBGraph::Client.new(:client_id => ENV["FACEBOOK_CLIENT_ID"],
                                     :secret_id =>ENV['FACEBOOK_SECRET_ID'],
                                     :token => ENV['FACEBOOK_TOKEN'])
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
      page_id = @config["id"]
      page = client.selection.page(page_id).info!
      url = page.link
      items = client
        .selection
        .page(page_id)
        .feed
        .until(range.max)
        .since(range.min)
        .info!
        .data
        .data || []
      items.map do |item|
        date = item.created_time.to_date
        title = item.message
        link = "#{url}/posts/#{item.object_id}"
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
        if item.date.nil?
          true
        else
          ! range.include?(item.date.to_date)
        end
      }.sort_by { |item|
        item.date.to_date
      }.map { |item|
        yield item
      }
    end

    def report(range)
      week_items(range).map { |item| "* #{item}\n" }
    end
  end
end
