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
          @files << file if file[-4..-1] == "emlx"
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
      this_month = month_products(products, Date.today.month)
      next_month = month_products(products, Date.today.next_month.month)
      print_products = -> month, products {
        sum = 0
        products.map { |p| puts p; sum += p.price }
        puts "#{month}月支払い合計:#{sum}円"
      }

      print_products.call(Date.today.month, this_month)
      print_products.call(Date.today.next_month.month, next_month)
    end


    def month_products(products, pay_month)
      pay_this_month = -> p_date, pay_month {
        (p_date.month == pay_month and p_date.day < 15) or
        (p_date.month == pay_month - 1 and p_date.day > 14)
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
      purchased_date, transfer_type, flg, body = nil, nil, nil, []
      return unless purchased_date = get_purchase_date(email)

      email.each_line do |line|
        if transfer_type ||= line[/^Content-Transfer-Encoding: (.*)/, 1] and not flg
          flg = true
          next
        elsif line[/^------=_Part_.*/, 0] and flg
          break
        end
        body << line if flg
      end
      [purchased_date, body, transfer_type]
    end

    def get_purchase_date(email)
      email.each_line do |line|
        purchased_date ||= line[/^Date:\s(.*)/, 1]
        if purchased_date
          unless is_this_or_before_month_shopping?(purchased_date)
            return nil
          else
            return purchased_date
          end
        end
      end
    end

    def is_this_or_before_month_shopping?(purchased_date)
      today = Date.today
      p_date = Date.parse(purchased_date)
      return false if p_date.year != today.year
      return false if p_date.month < (today.month - 2)
      return true
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
  # path = File.expand_path("~/Library/Mail/V2/AosIMAP-kankankan/amazon-confirm.mbox")
  # mr = MailReader.new(path)
  # mr.read_email
end


