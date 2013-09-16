# -*- coding: utf-8 -*-
require "nkf"
require 'base64'
require 'pry-debugger'
require 'find'
require 'date'

module ConfirmCalc

  class ConfirmMailReader
    def initialize(path)
      @path = File.expand_path(path)
      @files = []
      self.collect_emails
    end

    def collect_emails
      Find.find(@path) do |file|
        if File.directory?(file)
          next
        else
          @files << file if File.extname(file) == ".emlx"
        end
      end
    end

    def read_email
      products = []
      this_sum, next_sum = 0, 0

      @files.each do |file|
        File.open(file, "r") do |email|
          product = get_product_info(email)
          unless product
            next
          else
            products << product
          end
        end
      end
      sum_products(products)
    end

    def sum_products(products)
      this_month = 0
      print_products = -> month, products {
        sum = products.inject(0) { |s,p| puts p; s + p.price }
        puts "#{month}月支払い合計:#{sum}円"
      }

      if (1..10).include?(Date.today.day)
        this_month = Date.today.month
      else
        this_month = Date.today.month + 1
      end

      print_products.call(this_month, month_products(products, this_month))
      print_products.call(this_month+1, month_products(products, this_month+1))
    end

    def month_products(products, pay_month)
      pay_this_month = -> p_date, pay_month {
        (p_date.month == pay_month - 1 and p_date.day < 16) or
        (p_date.month == pay_month - 2 and p_date.day > 15)
      }
      month_products = []

      if Date.today.day < 16
        month_products = products.select do |p|
          pay_this_month.call(p.date, pay_month-1)
        end
      else
        month_products = products.select do |p|
          pay_this_month.call(p.date, pay_month)
        end
      end

      month_products
    end


    def get_product_info(email)
      purchased_date, body, transfer_type = get_email_info(email)
      return if body == nil or body.empty?

      if transfer_type == "base64"
        body = Base64.decode64(body.join("\n"))
      elsif transfer_type == "quoted-printable"
        body = NKF.nkf("-w -m0", body.join("\n").unpack("M*").join)
      end

      products, price = [], nil
      body.each_line do |line|
        products << line if line[/1 ".*"/,0]
        price ||= NKF.nkf("-w -m0", line)[/注文合計：.*?((?:(?:0|[1-9]\d{0,2}))(?:,\d{3})*)/,1]
      end
      Product.new(purchased_date, products, price)
    end

    def get_email_info(email)
      purchased_date, transfer_type, body = nil, nil, []
      return unless purchased_date = get_purchase_date(email)

      email.each_line do |line|
        case line
        when /^Content-Transfer-Encoding: (.*)/
          transfer_type = $1
          next
        when /^------=_Part_.*/
          break if transfer_type
        end
        body << line if transfer_type
      end
      [purchased_date, body, transfer_type]
    end

    def get_purchase_date(email)
      purchased_date = nil
      email.each_line do |line|
        case line
        when /^Date:\s(.*)/
          purchased_date = $1
          break
        end
      end

      unless is_this_or_before_month_shopping?(purchased_date)
        return nil
      else
        return purchased_date
      end
    end

    def is_this_or_before_month_shopping?(purchased_date)
      return false unless purchased_date
      today = Date.today
      p_date = Date.parse(purchased_date)
      if p_date.year != today.year or p_date.month < (today.month - 2)
        return false
      else
        return true
      end
    end
  end

  @cr = nil
  class << self
    def set_path(path)
      @cr = ConfirmMailReader.new(path)
    end

    def calc_month
      load File.expand_path("../box_config.rb", __FILE__)
      @cr.read_email
    end
  end
end

class Product
  attr_reader :date, :products, :price
  def initialize(date, products, price)
    @products = products
    @price = price.gsub(/,/, "").to_i
    @date = Date.parse(date)
  end

  def to_s
    puts @date
    puts @products
    puts @price.to_s + "円"
  end
end


if __FILE__ == $PROGRAM_NAME
  ConfirmCalc.calc_month
end


