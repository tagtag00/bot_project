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
# 9 18
    shortMa = eMovingAverage(3)
    middleMa = eMovingAverage(9)

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

def macd(shortRange = 12, middleRange = 26, signalRange = 9)

    macd = Hash.new { }
    value = []
    signal = 0
    sum = 0
    for i in 0..(signalRange - 1)
        value[i] = eMovingAverage(shortRange, i) - eMovingAverage(middleRange, i)
    end

    for i in 1..(signalRange - 1)
        sum += value[i]
    end
    signal = (sum + eMovingAverage(shortRange,1) + (2/6) * (value[0] - eMovingAverage(shortRange,1)) - eMovingAverage(middleRange,1) + (2/11) * (value[0] - eMovingAverage(middleRange,1))) / signalRange
    macd['value'] = value[0]
    macd['signal'] = signal

    return macd 
end

def macdTrend(shortRange = 12, middleRange = 26, signalRange = 9)

    macd_value = macd(shortRange, middleRange, signalRange)

    value = macd_value['value']
    signal = macd_value['signal']
    trade = "stay"
    
    if macd_value != 0
        if (value - signal) > 0     
            trade = "buy"
        elsif (value - signal) < 0
            trade = "sale"
        end
    end

    return trade
end

def stochastics(range = 14, priRange = 3)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    client.close

    if results.count < range + priRange then
        # puts "priData none."
        # trade = "stay"
        return false
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        pk = (res[0] - res.last(range).min) / (res.last(range).max - res.last(range).min) * 100



        return pk
    end
end

def getRangeTrend(range = 200, shortRange = 10, middleRange = 30, longRange = 300)
    sma = []
    trend = false

    sma[0] = sMovingAverage(shortRange)
    sma[1] = sMovingAverage(middleRange)
    sma[2] = sMovingAverage(longRange)

    if sma[2]
        value = sma.max - sma.min

        if value < range
            trend = true
        else
            trend = false
        end
    else
        trend = false
    end

    return trend
end

def bollingerBand(range = 20, priRange = 0)

    bollinger = Hash.new { }

    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data ORDER BY id DESC LIMIT #{range + priRange}")

    client.close

    if results.count < range + priRange then
        # puts "priData none."
        # trade = "stay"
        return 0
    else
        res = []
        i = 0
        results.each do |rows|
            res[i] = rows['price']
            i += 1
        end

        sma = sMovingAverage(range,priRange)

        if sma
            num1 = 0
            num2 = 0
            res.last(range).each do |rows|
                num1 += range * rows ** 2
                num2 += rows
            end

            value = Math.sqrt((num1 - (num2 ** 2)) / (range * (range - 1)))

            bollinger['midband'] = sma
            bollinger['plus1sigma'] = sma + value
            bollinger['plus2sigma'] = sma + value * 2
            bollinger['plus3sigma'] = sma + value * 3
            bollinger['minus1sigma'] = sma - value
            bollinger['minus2sigma'] = sma - value * 2
            bollinger['minus3sigma'] = sma - value * 3
            bollinger['nowPrice'] = res[0 + priRange]

            return bollinger
        else
            return 0
        end

    end
end

def bollingerTrigger(range = 10)
    value = Array.new(4)
    buyres = Array.new(3).map{Array.new(3,0)}
    saleres = Array.new(3).map{Array.new(3,0)}
    midres = Array.new(3)
    trigger = "stay"

    value[0] = bollingerBand(range, 0)
    value[1] = bollingerBand(range, 1)
    value[2] = bollingerBand(range, 2)
    value[3] = bollingerBand(range, 6)

    if value[3] != 0 
        buyres[0][0] = value[0]['nowPrice'] - value[0]['minus1sigma']
        buyres[0][1] = value[1]['nowPrice'] - value[1]['minus1sigma']
        buyres[0][2] = value[2]['nowPrice'] - value[2]['minus1sigma']

        buyres[1][0] = value[0]['nowPrice'] - value[0]['minus2sigma']
        buyres[1][1] = value[1]['nowPrice'] - value[1]['minus2sigma']
        buyres[1][2] = value[2]['nowPrice'] - value[2]['minus2sigma']

        buyres[2][0] = value[0]['nowPrice'] - value[0]['minus3sigma']
        buyres[2][1] = value[1]['nowPrice'] - value[1]['minus3sigma']
        buyres[2][2] = value[2]['nowPrice'] - value[2]['minus3sigma']        

        saleres[0][0] = value[0]['nowPrice'] - value[0]['plus1sigma']
        saleres[0][1] = value[1]['nowPrice'] - value[1]['plus1sigma']
        saleres[0][2] = value[2]['nowPrice'] - value[2]['plus1sigma']

        saleres[1][0] = value[0]['nowPrice'] - value[0]['plus2sigma']
        saleres[1][1] = value[1]['nowPrice'] - value[1]['plus2sigma']
        saleres[1][2] = value[2]['nowPrice'] - value[2]['plus2sigma']

        saleres[2][0] = value[0]['nowPrice'] - value[0]['plus3sigma']
        saleres[2][1] = value[1]['nowPrice'] - value[1]['plus3sigma']
        saleres[2][2] = value[2]['nowPrice'] - value[2]['plus3sigma']

        midres[0] = value[0]['nowPrice'] - value[0]['midband']
        midres[1] = value[1]['nowPrice'] - value[1]['midband']
        midres[2] = value[2]['nowPrice'] - value[2]['midband']

        row = (value[3]['plus3sigma'] - value[3]["minus3sigma"]) / (value[0]['plus3sigma'] - value[0]["minus3sigma"])

        if buyres[2][0] > 0 && buyres[2][1] < 0 && buyres[2][2] < 0
            trigger = "buy"
        elsif buyres[1][0] > 0 && buyres[1][1] < 0 && buyres[1][2] < 0
            trigger = "buy"
        elsif saleres[2][0] < 0 && saleres[2][1] > 0 && row > 0.9
            trigger = "sale"
        elsif saleres[1][0] < 0 && saleres[1][1] > 0 && row > 0.9
            trigger = "sale"               
        end
    end

    return trigger
end

def bollingerTrend(range = 10)

    value = bollingerBand(range, 0)

    if value != 0 
        buyres = value['nowPrice'] - value['minus2sigma']

        saleres = value['nowPrice'] - value['plus1sigma']

        if buyres > 0
            trend = "buy"
        elsif saleres < 0
            trend = "sale"
        else
            trend = "stay"
        end
    else
        trend = "stay"
    end

    return trend
end

def getTradeState()
    # dstate = differenceApproximation()
    # rsi = relativeStrengthIndex(14)
    # if rsi 
    # else 
    #     rsi = 50
    # end
    macdT = macdTrend()
    bbtrigger = bollingerTrigger(105)

    # mac = macd(6,14,6)
    # macValue = mac['value'] - mac['signal']
    # mstate = maCross()
    # puts "ma disp:" + (nowMaDisp = wMovingAverage(200) - wMovingAverage(200,1)).to_s
    # puts "mstate:" + mstate = maCross()
    # trend = maTrend()

    # if dstate == "sale" || mstate == "sale"&& rsi > 70 
    # if dstate == "sale" && rsi > 50 && trend == "sale"
    # if dstate == "sale" && rsi > 52 && macValue < 0 && trend == "sale"
    if macdT == "sale" && bbtrigger == "sale"
        trade = "sale"
    # elsif dstate == "buy" && trend == "buy" || mstate == "buy" && rsi < 30
    # elsif dstate == "buy" && trend == "buy" && rsi < 40
    # elsif dstate == "buy" && rsi < 28 && macValue > 0
    elsif macdT == "buy" && bbtrigger == "buy"
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
    # https = Net::HTTP.new(uri.host, uri.port)
    # https.use_ssl = true
    # response = https.request(options)
    # result = JSON.parse(response.body)

    # puts result

    # return result

    begin
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        response = https.request(options)

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

orderList = []
stopOrder = 4000 

client.query("DELETE FROM trade_data")
# client.query("DELETE FROM tick_data")
# orderSize = 0.01 * 0.999 * 0.999
# orderSize = BigDecimal(orderSize.to_s).floor(4).to_f # 1.234
# order("BTC_JPY","SELL",orderSize)

loop do

    results = getBalance()
    
    if results != false
        puts "My Balance JPY :" + results[0]['amount'].to_s + "   BTC :" + results[1]['amount'].to_s
    end

    ownCoin = results[1]['amount']
    
    result = getTicker

    if result != false
        puts time = DateTime.parse(result['timestamp']) + Rational(9,24)
        puts "nowPrice: " + result['ltp'].to_s

        client.query("INSERT INTO tick_data (timestamp, price) VALUES ('#{time}','#{result['ltp']}')")

        puts "trade:" + trade = getTradeState()

        # STOP ODER
        if orderList.length != 0
            orderavg = orderList.inject(0.0){|r,i| r+=i }/orderList.size
            val = orderavg - result['ltp']
            if val > stopOrder
                trade = 'sale'
                puts "損切り"
            end
        end

        case trade
        when 'sale' then
            if ownCoin > 0.009
                query = "INSERT INTO trade_data (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{ownCoin}','#{result['ltp']}',0)"
                client.query(query)
                trade_result += ownCoin * result['ltp']
                commission += ownCoin * result['ltp'] * 0.001
                ownCoin = 0

                # オーダー
                orderSize = results[1]['amount'] * 0.999
                orderSize = BigDecimal(orderSize.to_s).floor(4).to_f
                order("BTC_JPY","SELL",orderSize)

                # ORDER LIST RESET
                orderList = []
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

                # ORDER LIST ADD
                orderList.push(result['ltp'])
            end
        end
    end

    puts "trade_result:" + trade_result.to_s + "   commission:" + commission.to_s
    puts ownCoin
    sleep (5)
end


