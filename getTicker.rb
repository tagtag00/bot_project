#!/home/vagrant/.rbenv/shims/ruby

require 'uri'
require 'net/http'
require 'time'
require 'securerandom'
require 'base64'
# require 'rest-client'
require 'json'
require 'mysql2'
require 'date'

API_KEY = ENV['bfkey']
API_SECRET = ENV['bfsecret']

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

    begin
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        response = https.get uri.request_uri

        case response
        when Net::HTTPSuccess
            result = JSON.parse(response.body)
            return result
        when Net::HTTPRedirection
            location  = response['location']
            warn "redirected to #{location}"
        else
            puts [uri.to_s, response.value].join(" : ")
            nil
        end
    rescue => e
        puts [uri.to_s, e.class, e].join(" : ")
        nil
    end

	return false
end

def differenceApproximation()

    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT 3")

    client.close

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

# 単純移動平均(SMA)
def sMovingAverage(range = 10,priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    client.close

    if results.count < range + priRange then
        puts "priData none."
        trade = "stay"
        return false
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        sma = res[priRange..-1].inject(:+) / range

        return sma
    end
end

# 加重移動平均(WMA)
def wMovingAverage(range = 10,priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    client.close

    if results.count < range + priRange then
        puts "priData none."
        trade = "stay"
        return false
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        num = 0
        total = 0
        i = res.length - priRange
        res.last(range).each do |rows|
            total += rows * i
            num += i
            i -= 1
        end

        wma = total / num

        return wma
    end
end

# 指数移動平均(EMA)
def eMovingAverage(range = 10,priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + range + priRange}")

    client.close

    if results.count < range + priRange then
        puts "priData none."
        trade = "stay"
        return false
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        sma = sMovingAverage(range,range + priRange + 1)

        if sma
            # ema = sma + ( 2 / (range + 1)) * (res[(range + priRange - 1)] - res[(range + priRange)])
            ema = ((sma * (range - 1)) + (res[(range + priRange - 1)] * 2)) / (range + 1)

            res[priRange..(range + priRange -1)].reverse_each do |rows|
                total = (ema * (range - 1)) + (rows * 2)
                ema = total / (range + 1)
                # ema = ema + ( 2 / (range + 1)) * (rows - ema)
            end
        else
            return false
        end 

        return ema
    end
end

# RSI
def relativeStrengthIndex(range = 10, priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    client.close

    if results.count < range + priRange then
        puts "priData none."
        trade = "stay"
        return false
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        anum = 0
        bnum = 0

        for i in priRange..res.length - 2 do

            num = res[i] - res[i + 1]
            if num > 0
                anum += num
            else
                bnum += num
            end
        end

        a = anum / range
        b = bnum / range * -1

        rsi = a / (a + b) * 100

        return rsi

    end

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

    # puts "shortMa:" + shortMa[0].to_s
    # puts "middleMa:" + middleMa[0].to_s
if shortMa[3] && middleMa[3]
    # if shortMa[0] > shortMa[1] && middleMa[0] < middleMa[1] && (shortMa[1] - middleMa[1]) > 0 && (shortMa[2] - middleMa[2]) < 0 && shortMa[2] > shortMa[3] && middleMa[2] < middleMa[3]
    if (shortMa[0] - middleMa[0]) > 0 && (shortMa[1] - middleMa[1]) < 0     
        trade = "buy"
    # elsif shortMa[0] < shortMa[1] && middleMa[0] > middleMa[1] && (shortMa[1] - middleMa[1]) < 0 && (shortMa[2] - middleMa[2]) > 0 && shortMa[2] < shortMa[3] && middleMa[2] > middleMa[3]
    elsif (shortMa[0] - middleMa[0]) < 0 && (shortMa[1] - middleMa[1]) > 0
        trade = "sale"
    else
        trade = "stay"
    end
else
    trade = "stay"
end

    return trade
end

def maTrend()

    shortMa = eMovingAverage(9)
    middleMa = eMovingAverage(18)

    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT 1")

    client.close
res = 0
    results.each do |rows|
        res = rows['price']
    end

    if shortMa && middleMa
        # posi = res - shortMa
        posi = shortMa - middleMa
        posi_now = res - shortMa
        if posi > 0
            trade = "buy"
        elsif posi < 0
            trade = "sale"
        else
            trade = "stay"
        end
    else
        trade = "stay"
    end

    return trade
end

def macd()

    macd = Hash.new { }

    macd['value'] = eMovingAverage(12, 0) - eMovingAverage(26, 0)


end

def getTradeState()
    dstate = differenceApproximation()
    rsi = relativeStrengthIndex(14)
    if rsi 
    else 
        rsi = 50
    end

    # mstate = maCross()
    # puts "ma disp:" + (nowMaDisp = wMovingAverage(200) - wMovingAverage(200,1)).to_s
    # puts "mstate:" + mstate = maCross()
    trend = maTrend()

    # if dstate == "sale" || mstate == "sale"&& rsi > 70 
    if dstate == "sale" && rsi > 50 && trend == "sale"
        trade = "sale"
    # elsif dstate == "buy" && trend == "buy" || mstate == "buy" && rsi < 30
    elsif dstate == "buy" && trend == "buy" && rsi < 40
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

    # puts result

    return result
end

def order(product_code = "BTC_JPY", buy_sell, size)
    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/sendchildorder"

    body = '{
        "product_code" : "' + product_code + '",
        "child_order_type" : "MARKET",
        "side" : "' + buy_sell + '",
        "size" : ' + size.to_s + ',
        "minute_to_expire" : 10000,
        "time_in_force" : "GTC"
    }'

    text = timestamp + 'POST' + uri.request_uri + body
    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Post.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

    options.body = body
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    response = https.request(options)
    result = JSON.parse(response.body)

    if (result['status'] == -201) then
        puts ' ' + product_code + ' ' + buy_sell + " You have reached the maximum amount of trades for your account class."
        return false
    end
    if (result['child_order_acceptance_id'] == nil) then
        puts ' ' + product_code + ' ' + buy_sell + " Insufficient funds"
        return false
    end 
    if (result['child_order_acceptance_id'] != nil) then
        puts ' ' + product_code + ' ' + buy_sell + " id:" + result['child_order_acceptance_id'] + " size:" + size.to_s
    end

    return true
end

# getBalance
#getTicker

client = Mysql2::Client.new(
  :host => "localhost",
  :username => "root",
  :password => "taguri",
  :database => "bot_db"
)

maxCoin = 0.1
tradingUnit = 0.01
ownCoin = 0.0
trade_result = 0
commission = 0

client.query("DELETE FROM trade_data")
# client.query("DELETE FROM tick_data")
# orderSize = 0.01 * 0.999 * 0.999
# orderSize = BigDecimal(orderSize.to_s).floor(4).to_f # 1.234
# order("BTC_JPY","SELL",orderSize)

loop do

    results = getBalance()
    puts "My Balance JPY :" + results[0]['amount'].to_s + "   BTC :" + results[1]['amount'].to_s

    result = getTicker

    puts time = DateTime.parse(result['timestamp']) + Rational(9,24)
    puts "nowPrice: " + result['ltp'].to_s

    client.query("INSERT INTO tick_data (timestamp, price) VALUES ('#{time}','#{result['ltp']}')")

    puts "trade:" + trade = getTradeState()

    case trade
    when 'sale' then
        if ownCoin > 0
            query = "INSERT INTO trade_data (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{ownCoin}','#{result['ltp']}',0)"
            client.query(query)
            trade_result += ownCoin * result['ltp']
            commission += ownCoin * result['ltp'] * 0.001
            ownCoin = 0

            # オーダー
            orderSize = results[1]['amount'] * 0.999
            orderSize = BigDecimal(orderSize.to_s).floor(4).to_f
            order("BTC_JPY","SELL",orderSize)
        end
    when 'buy' then
        if ownCoin < maxCoin
            ownCoin += tradingUnit
            query = "INSERT INTO trade_data (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{tradingUnit}','#{result['ltp']}','#{ownCoin}')"
            client.query(query)
            trade_result += result['ltp'] * -1 * tradingUnit
            commission += result['ltp'] * 0.001 * tradingUnit

            # オーダー
            order("BTC_JPY","BUY",tradingUnit)
        end
    end

    puts "trade_result:" + trade_result.to_s + "   commission:" + commission.to_s
    puts ownCoin
    sleep (5)
end


