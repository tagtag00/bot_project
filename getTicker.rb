#!/home/vagrant/.rbenv/shims/ruby

require 'uri'
require 'net/http'
require 'time'
require 'securerandom'
require 'base64'
#require 'rest-client'
require 'json'
require 'mysql2'
require 'date'

# API_KEY = ENV['bfkey']
# API_SECRET = ENV['bfsecret']

markets = 'https://api.bitflyer.jp/v1/getmarkets'
ticker = 'https://api.bitflyer.jp/v1/getticker?product_code=BTC_JPY'
executions = 'https://api.bitflyer.jp/v1/executions?product_code=BTC_JPY'
ohlc = 'https://api.cryptowat.ch/markets/bitflyer/btcjpy/ohlc'
ohlc2 = 'https://api.cryptowat.ch/markets/bitflyer/btcjpy/ohlc?periods=86400&after=86500'

# response = RestClient.get(markets)
# puts JSON.parse(response.body)

def getTicker(product_code = 'BTC_JPY')
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/getticker"
    uri.query = 'product_code=' + product_code

	https = Net::HTTP.new(uri.host, uri.port)
	https.use_ssl = true
	response = https.get uri.request_uri
	result = JSON.parse(response.body)

	return result
end

def differenceApproximation()

    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT 3")

    if results.count < 3 then
        puts "priData none."
        trade = "stay"
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        nowPriceDisp = res[0] - res[1]
        priPriceDisp = res[1] - res[2]

        if priPriceDisp >= 0 && nowPriceDisp < 0
            trade = "sale"
        elsif priPriceDisp <= 0 && nowPriceDisp > 0
            trade = "buy"
        else
            trade = "stay"
        end
    end

    return trade
end

def sMovingAverage(range = 10,priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    res = []
    i = 0
    results.each do |rows|
        res[i] = rows['price']
        i += 1
    end

    ma = res[priRange..-1].inject(:+) / range

    return ma
end

def wMovingAverage(range = 10,priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    res = []
    i = 0
    results.each do |rows|
        res[i] = rows['price']
        i += 1
    end

    num = 0
    total = 0
    res[priRange..-1].each do |rows|
        total += rows * (i + 1)
        num += (i + 1) 
        i -= 1
    end

    wma = total / num

    return wma
end

def eMovingAverage(range = 10,priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + range + priRange}")

    res = []
    i = 0
    results.each do |rows|
        res[i] = rows['price']
        i += 1
    end

    sma = sMovingAverage(range,range + priRange)
    ema = ((sma * (range - 1)) + (res[(range + priRange - 1)] * 2)) / (range + 1)

    res[priRange..(range + priRange -1)].reverse_each do |rows|
        total = (ema * (range - 1)) + (rows * 2)
        ema = total / (range + 1)
    end        

    return ema
end

def maCross()
    shortMa = []
    middleMa = []

    for i in 0..3
        shortMa[i] = eMovingAverage(10,i)
    end

    for i in 0..3
        middleMa[i] = eMovingAverage(30,i)
    end

    if shortMa[0] > shortMa[1] && middleMa[0] < middleMa[1] && (shortMa[1] - middleMa[1]) > 0 && (shortMa[2] - middleMa[2]) < 0 && shortMa[2] > shortMa[3] && middleMa[2] < middleMa[3]
        trade = "buy"
    elsif shortMa[0] < shortMa[1] && middleMa[0] > middleMa[1] && (shortMa[1] - middleMa[1]) < 0 && (shortMa[2] - middleMa[2]) > 0 && shortMa[2] < shortMa[3] && middleMa[2] > middleMa[3]
        trade = "sale"
    else
        trade = "stay"
    end

    return trade
end

def macd()

    macd = eMovingAverage(12, 0) - eMovingAverage(26, 0)



end

def getTradeState()
    puts "dstate:" + dstate = differenceApproximation()
    puts "ma disp:" + (nowMaDisp = wMovingAverage(200) - wMovingAverage(200,1)).to_s
    puts "mstate:" + mstate = maCross()

    if dstate == "sale" && nowMaDisp < 0 || mstate == "sale"
        trade = "sale"
    elsif dstate == "buy" && nowMaDisp > 0 || mstate == "buy"
        trade = "buy"
    else
        trade = "stay"
    end

    return trade
end

def getBalance()
    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getbalance"

    text = timestamp + 'GET' + uri.request_uri
    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    response = https.request(options)
    result = JSON.parse(response.body)

    puts result

    return true
end

#getBalance
#getTicker

client = Mysql2::Client.new(
  :host => "localhost",
  :username => "root",
  :password => "taguri",
  :database => "bot_db"
)

maxCoin = 10
ownCoin = 0

client.query("DELETE FROM trade_data")

loop do

    result = getTicker

    client.query("INSERT INTO tick_data (timestamp, price) VALUES ('#{result['timestamp']}','#{result['ltp']}')")

    puts time = DateTime.parse(result['timestamp']) + Rational(9,24)
    puts "nowPrice: " + result['ltp'].to_s

    puts "trade:" + trade = getTradeState()

    case trade
    when 'sale' then
        if ownCoin > 0
            query = "INSERT INTO trade_data (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{ownCoin}','#{result['ltp']}',0)"
            client.query(query)
            ownCoin = 0
        end
    when 'buy' then
        if ownCoin < maxCoin
            ownCoin += 1
            query = "INSERT INTO trade_data (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}',1,'#{result['ltp']}','#{ownCoin}')"
            client.query(query)
        end
    end

    puts ownCoin

    sleep (10)
end


