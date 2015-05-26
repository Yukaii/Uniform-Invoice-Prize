require 'curb'
require 'nokogiri'
require 'pry'
require 'yaml'
require 'thread/pool'
require 'XDDCrawler'

class Lottery
  include XDDCrawler::ASPEssential
  attr_reader :so_special_price, :special_price, :head_prices, :additional_sixth_prices, :year, :draw_month, :start_month, :end_month, :records

  PRICE = {
    "特別獎" => 10_000_000,
    "特獎" => 2_000_000,
    "頭獎" => 200_000,
    "二獎" => 40_000,
    "三獎" => 10_000,
    "四獎" => 4_000,
    "五獎" => 1_000,
    "六獎" => 200,
    "增開六獎" => 200,
    "掰掰" => 0,
  }

  def initialize(time: Time.now)
    super
  end

  def reload(time: Time.now)
    load_record
  end

  def check_lottery invoice_code=nil, time: nil, year: Time.now.year, month: Time.now.month, day: Time.now.day
    if not time.nil?
      setup(time)
    else
      setup Time.new(year, month, day)
    end

    return "錯誤" if @so_special_price.nil? || @special_price.nil? || @head_prices.nil? || @additional_sixth_prices.nil?
    return "特別獎" if invoice_code == @so_special_price
    return "特獎" if invoice_code == @special_price

    @head_prices.each{|head| return "頭獎" if invoice_code == head }
    @head_prices.each{|head| return "二獎" if invoice_code[1..-1] == head[1..-1] }
    @head_prices.each{|head| return "三獎" if invoice_code[2..-1] == head[2..-1] }
    @head_prices.each{|head| return "四獎" if invoice_code[3..-1] == head[3..-1] }
    @head_prices.each{|head| return "五獎" if invoice_code[4..-1] == head[4..-1] }
    @head_prices.each{|head| return "六獎" if invoice_code[5..-1] == head[5..-1] }

    @additional_sixth_prices.each{|six| return "增開六獎" if invoice_code[-3..-1] == six}

    return "掰掰"
  end

  private
    def setup time
      @year = time.year - 1911
      @draw_month = get_draw_month(time)
      @start_month, @end_month = get_lottery_months(@draw_month)

      load_record

      if fetch_lottery.nil?
        fetch_online_lottery
        save_record
      end
    end

    def fetch_lottery
      # load record
      record = @records.select do |rec|
        rec.has_key?("year") && rec.has_key?("start_month") && rec.has_key?("end_month") && rec["year"] == @year && rec["start_month"] == @start_month && rec["end_month"] == @end_month
      end
      lottery_info = record.empty? ? nil : record.first

      if not lottery_info.nil?
        @so_special_price = lottery_info["so_special_price"]
        @special_price = lottery_info["special_price"]
        @head_prices = lottery_info["head_prices"]
        @additional_sixth_prices = lottery_info["additional_sixth_prices"]
        return true
      else
        return nil
      end
    end

    def fetch_online_lottery
      # not record found
      visit "http://www.etax.nat.gov.tw/etwmain/front/ETW183W1"
      # lottery_lists = [
      #   ["ETW183W2?id=14c4f826ecb00000aae8b5c3346d4493", "104年01月、02月"],
      #   ["ETW183W2?id=14b1f79bc5700000a9ef78b1708be70d", "103年11月、12月"],
      #   ["ETW183W2?id=149e58cdb5a00000d2d54a98932994cb", "103年09月、10月"],
      #   ...
      # ]
      lottery_lists = @doc.css('#searchForm a').map{|node| [node[:href], node.text]}.select{|arr| !!arr[1].match(/(?<year>\d+)年(?<m1>\d+)月、(?<m2>\d+)月/)}

      # pool = Thread.pool(20)

      lottery_lists.each do |lot|
        # pool.process do
          doc = Nokogiri::HTML(RestClient.get("http://www.etax.nat.gov.tw/etwmain/front/#{lot[0]}").to_s.force_encoding('utf-8'))
          rows = doc.css('table.table_b tr')

          m = doc.css('h4').text.match(/(?<year>\d+)年(?<m1>\d+)月、(?<m2>\d+)月/)
          year = m[:year].to_i
          start_month = m[:m1].to_i
          end_month = m[:m2].to_i
          so_special_price = rows.xpath(td_xpath "特別獎" ).text.strip
          special_price = rows.xpath(td_xpath "特獎" ).text.strip
          head_prices = rows.xpath(td_xpath "頭獎" ).text.strip.split('、')
          additional_sixth_prices = rows.xpath(td_xpath "增開六獎" ).text.strip.split('、')

          @records << {
            "year" => year,
            "start_month" => start_month,
            "end_month" => end_month,
            "so_special_price" => so_special_price,
            "special_price" => special_price,
            "head_prices" => head_prices,
            "additional_sixth_prices" => additional_sixth_prices,
          }
        # end # pool.process do
      end # lottery_lists.each
      # pool.shutdown
    end # fetch_online_lottery

    def get_draw_month time=Time.now
      if time.month % 2 == 1
        if time.day >= 25 # 奇數月開獎後那幾天
          return time.month
        else
          return time.month-2 < 0 ? (time.month-2 + 12) : time.month-2
        end
      else # 偶數月
        return time.month-1
      end
    end

    def get_lottery_months draw_month=get_draw_month
      draw_month = get_draw_month(draw_month) if draw_month % 2 == 0
      return (draw_month-2 + 12)%12, (draw_month-2 + 12)%12 + 1
    end

    def td_xpath(th)
      return "\/\/th\[.=\"#{th}\"\]\/ancestor::tr\/td"
    end

    def load_record
      @record_filename = 'RECORD.yaml'
      if File.exist?(@record_filename)
        @records = YAML.load(File.read(@record_filename))
      else
        @records = []
      end
    end

    def save_record
      File.open(@record_filename, 'w') {|f| f.write(@records.sort_by{|rec| "#{@year}#{@end_month}".to_i}.to_yaml)}
    end

  # private methods end
end

lottery = Lottery.new
puts lottery.check_lottery "04296940"
puts lottery.check_lottery "43772058"
binding.pry
puts "hello"
