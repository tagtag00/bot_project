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
        return "stay"
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
            "sale"
        elsif priPriceDisp <= 0 && nowPriceDisp > 0
            "buy"
        else
            "stay"
        end
    end
end

def movingAverage(range = 10,priRange = 0)
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

def getTradeState()
    puts state = differenceApproximation()
    nowMaDisp = movingAverage(200) - movingAverage(200,1)

    if state = "sale" && nowMaDisp < 0
        "sale"
    elsif state = "buy" && nowMaDisp > 0
        "buy"
    else
        "state"
    end
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

    trade = getTradeState()

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

# puts movingAverage(200)
# puts movingAverage(200,1)
# puts movingAverage(10)
# puts movingAverage(10,1)
# puts movingAverage(30)
# puts movingAverage(30,1)

    sleep (10)
end


