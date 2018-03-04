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

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT 3")

    client.close

    if results.count < 3 then
        # puts "priData none."
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

        if priPriceDisp > 0 && nowPriceDisp < 0
            trade = "sale"
        elsif priPriceDisp < 0 && nowPriceDisp > 0
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

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT #{range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT #{range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT #{range + range + priRange}")

    client.close

    if results.count < range + priRange then
        # puts "priData none."
        return 0
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
            return 0
        end

        return ema
    end
end

# RSI
def relativeStrengthIndex(range = 14, priRange = 0)
    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT #{range + priRange}")

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

def maTrend(shortRange = 9, middleRange = 18)

    shortMa = eMovingAverage(shortRange)
    middleMa = eMovingAverage(middleRange)

    client = Mysql2::Client.new(
      :host => "localhost",
      :username => "root",
      :password => "taguri",
      :database => "bot_db"
    )

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT 1")

    client.close
res = 0
    results.each do |rows|
        res = rows['price']
    end

    if shortMa && middleMa
        # posi = res - shortMa
        posi = shortMa - middleMa
        posi_now = res - shortMa
        if posi_now > 0
            trade = "buy"
        elsif posi_now < 0
            trade = "sale"
        else
            trade = "stay"
        end
    else
        trade = "stay"
    end

    return trade
end

def macd(shortRange = 12, middleRange = 26, signalRange = 9, priRange = 0)

    macd = Hash.new { }
    value = []
    signal = 0
    sum = 0
    for i in (0 + priRange)..(signalRange - 1 + priRange)
        value[i] = eMovingAverage(shortRange, i) - eMovingAverage(middleRange, i)
    end

    for i in (1 + priRange)..(signalRange - 1 + priRange)
        sum += value[i]
    end
    signal = (sum + eMovingAverage(shortRange,(1 + priRange)) + (2/6) * (value[(0 + priRange)] - eMovingAverage(shortRange,(1 + priRange))) - eMovingAverage(middleRange,(1 + priRange)) + (2/11) * (value[(0 + priRange)] - eMovingAverage(middleRange,(1 + priRange)))) / signalRange
    macd['value'] = value[(0 + priRange)]
    macd['signal'] = signal

    return macd 
end

def macdCross(shortRange = 12, middleRange = 26, signalRange = 9)

    result = []
    value = []
    trade = "stay"

    result[0] = macd(shortRange,middleRange,signalRange,0)
    result[1] = macd(shortRange,middleRange,signalRange,1)
    result[2] = macd(shortRange,middleRange,signalRange,2)

    # puts "now:" + result[0]['value'].to_s + "  pri:" + result[1]['value'].to_s + "  pri:" + result[2]['value'].to_s

    value[0] = result[0]['value'] - result[0]['signal']
    value[1] = result[1]['value'] - result[1]['signal']
    value[2] = result[2]['value'] - result[2]['signal']
    # value[2] = result[1]['value'] - result[2]['value']
    # value[3] = result[1]['value'] - result[2]['value']

    # puts "now:" + value[0].to_s + "  pri:" + value[1].to_s

    if value[0] > 0 && value[1] < 0 && result[0]['value'] > 0
        trade = "sale"
        # puts "buy"
    elsif value[0] < 0 && value[1] > 0  && result[0]['value'] < 0
        trade = "buy"
        # puts "sale"
    end
    
    return trade
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

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT #{range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll_test ORDER BY id DESC LIMIT #{range + priRange}")

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
    value = []
    buyres = Array.new(3).map{Array.new(3,0)}
    saleres = Array.new(3).map{Array.new(3,0)}
    midres = Array.new(3)
    trigger = "stay"

    value[0] = bollingerBand(range, 0)
    value[1] = bollingerBand(range, 1)
    value[2] = bollingerBand(range, 2)
    value[3] = bollingerBand(range, 6)

    # macd_value = macd(30, 90, 20)
    # trend = maTrend(6,12)
    # rangeTrend = getRangeTrend(10000, 12, 26, 200)

    if value[3] != 0 
        buyres[0][0] = value[0]['nowPrice'] - value[0]['minus1sigma']
        buyres[0][1] = value[1]['nowPrice'] - value[1]['minus1sigma']
        buyres[0][2] = value[2]['nowPrice'] - value[2]['minus1sigma']
        # buyres[3] = value[3]['nowPrice'] - value[3]['minus1sigma']
        buyres[1][0] = value[0]['nowPrice'] - value[0]['minus2sigma']
        buyres[1][1] = value[1]['nowPrice'] - value[1]['minus2sigma']
        buyres[1][2] = value[2]['nowPrice'] - value[2]['minus2sigma']

        buyres[2][0] = value[0]['nowPrice'] - value[0]['minus3sigma']
        buyres[2][1] = value[1]['nowPrice'] - value[1]['minus3sigma']
        buyres[2][2] = value[2]['nowPrice'] - value[2]['minus3sigma']        

        saleres[0][0] = value[0]['nowPrice'] - value[0]['plus1sigma']
        saleres[0][1] = value[1]['nowPrice'] - value[1]['plus1sigma']
        saleres[0][2] = value[2]['nowPrice'] - value[2]['plus1sigma']
# puts value[0]
# puts value[1]
# puts "saleres0: #{saleres[0][0]} = #{value[0]['nowPrice']} - #{value[0]['plus1sigma']}"
# puts "saleres1: #{saleres[0][1]} = #{value[1]['nowPrice']} - #{value[1]['plus1sigma']}"
        saleres[1][0] = value[0]['nowPrice'] - value[0]['plus2sigma']
        saleres[1][1] = value[1]['nowPrice'] - value[1]['plus2sigma']
        saleres[1][2] = value[2]['nowPrice'] - value[2]['plus2sigma']

        saleres[2][0] = value[0]['nowPrice'] - value[0]['plus3sigma']
        saleres[2][1] = value[1]['nowPrice'] - value[1]['plus3sigma']
        saleres[2][2] = value[2]['nowPrice'] - value[2]['plus3sigma']

        midres[0] = value[0]['nowPrice'] - value[0]['midband']
        midres[1] = value[1]['nowPrice'] - value[1]['midband']
        midres[2] = value[2]['nowPrice'] - value[2]['midband']

        # midres[3] = value[0]['midband'] - value[1]['midband']

        row = (value[3]['plus3sigma'] - value[3]["minus3sigma"]) / (value[0]['plus3sigma'] - value[0]["minus3sigma"])

        # macdres = macd_value['value'] - macd_value['signal']
        
        if buyres[2][0] > 0 && buyres[2][1] < 0 && buyres[2][2] < 0
            trigger = "buy"
        elsif buyres[1][0] > 0 && buyres[1][1] < 0 && buyres[1][2] < 0
            trigger = "buy"
        # elsif buyres[0][0] > 0 && buyres[0][1] < 0 && buyres[0][2] < 0
        #     trigger = "buy"
        # elsif midres[0] > 0 && midres[1] < 0 && midres[2] < 0
        #     trigger = "buy" 
        elsif saleres[2][0] < 0 && saleres[2][1] > 0 && saleres[2][2] > 0
            trigger = "sale"
        elsif saleres[1][0] < 0 && saleres[1][1] > 0 && saleres[1][2] > 0
            trigger = "sale"
        # elsif saleres[0][0] < 0 && saleres[0][1] > 0 && saleres[0][2] > 0
        #     trigger = "sale"
        # elsif midres[0] < 0  && midres[1] > 0 && midres[2] > 0
        #     trigger = "sale"
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
    rsi = relativeStrengthIndex(14)
    # stc = stochastics(14)
    if rsi
    else 
        rsi = 50
        # stc = 50
    end
    # macdT = macdTrend()
    # bbtrigger = bollingerTrigger(60)
    # bbtrend = bollingerTrend(20)
    mcross = macdCross(20, 52, 9)
    # mac = macd(10,26,9)
    # macRenge = mac['value'] * mac['signal']
    # macValue = mac['value'] - mac['signal']

    # mstate = maCross()
    # nowMaDisp = wMovingAverage(200) - wMovingAverage(200,36)
    # puts "mstate:" + mstate = maCross()
    # trend = maTrend(9,18)

# if trend == "sale"
#dstate == "sale" && rsi > 50 && trend == "sale" && trend == "sale" && macValue < 0  bbtrigger == "sale"  && rsi > 50
    if mcross == "sale"
    # if dstate == "sale" && bbtrend == "sale" && rsi > 50 && macValue < 0
        trade = "sale"
#dstate == "buy" && trend == "buy" && rsi < 40 && trend == "buy" && macValue > 0 bbtrigger == "buy"  && rsi < 35
    elsif mcross == "buy"
    # elsif dstate == "buy" && bbtrend == "buy" && rsi < 28 && macValue > 0
        trade = "buy"
    else
        trade = "stay"
    end
# else
#     if dstate == "sale" && rsi > 52 && macValue < 0
#         trade = "sale"
#     # elsif dstate == "buy" && trend == "buy" || mstate == "buy" && rsi < 30
#     # elsif dstate == "buy" && trend == "buy" && rsi < 40
#     elsif dstate == "buy" && rsi < 28 && macValue > 0
#         trade = "buy"
#     else
#         trade = "stay"
#     end
# end

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

maxCoin = 0.8
tradingUnit = 0.1
ownCoin = 0.0
trade_result = 0
commission = 0

orderList = []
stopOrder = 1000
profitOrder = 5000

client.query("DELETE FROM trade_data_coll_test")

client.query("DELETE FROM tick_data_coll_test")
# client.query("DELETE FROM tick_data_coll_test_bb")
results = client.query("SELECT * FROM tick_data_coll")

# loop do
results.each do |rows|
    # result = getTicker('FX_BTC_JPY')

    
    client.query("INSERT INTO tick_data_coll_test (timestamp, price) VALUES ('#{rows['timestamp']}','#{rows['price']}')")

    time = rows['timestamp']
    # puts "nowPrice: " + rows['price'].to_s

    trade = getTradeState()

# value = {}
# value = bollingerBand(60, 0)
# macd_value = macd(10, 26, 9)
# rsi_value = relativeStrengthIndex(14)
# if value != 0
# query = ("INSERT INTO tick_data_coll_test_bb (timestamp, price, bbmidband, bbplus1sigma, bbplus2sigma, bbplus3sigma, bbminus1sigma, bbminus2sigma, bbminus3sigma, macd_value, macd_signal, rsi_value) VALUES ('#{rows['timestamp']}','#{rows['price']}','#{value['midband']}','#{value['plus1sigma']}', '#{value['plus2sigma']}', '#{value['plus3sigma']}', '#{value['minus1sigma']}', '#{value['minus2sigma']}', '#{value['minus3sigma']}', #{macd_value['value']}, #{macd_value['signal']}, #{rsi_value})")
# client.query(query)
# end

    if orderList.length != 0
        orderavg = orderList.inject(0.0){|r,i| r+=i }/orderList.size
        val = orderavg - rows['price']
        val2 = rows['price'] - orderavg
        if val > stopOrder
            trade = 'sale'
            puts "損切り"
        elsif val2 > profitOrder
            trade = 'sale'
            puts "利確"
        end
    end

    case trade
    when 'sale' then
        if ownCoin > 0
            # query = "INSERT INTO trade_data_test (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{ownCoin}','#{rows['price']}',0)"
            # client.query(query)
            trade_result += ownCoin * rows['price']
            # commission += ownCoin * rows['price'] * 0.001
            ownCoin = 0
            puts "time:" + time.to_s + "trade_result:" + trade_result.to_s

            orderList = []
        end
    when 'buy' then
        if ownCoin < maxCoin
            ownCoin += tradingUnit
            # query = "INSERT INTO trade_data_test (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{tradingUnit}','#{rows['price']}','#{ownCoin}')"
            # client.query(query)
            trade_result += rows['price'] * -1 * tradingUnit
            # commission += rows['price'] * 0.001 * tradingUnit
            puts "time:" + time.to_s + "trade_result:" + trade_result.to_s

            orderList.push(rows['price'])

        end
    end
# puts "nowTime: " + rows['timestamp'].to_s + "  nowPrice: " + rows['price'].to_s + "  trade_result:" + trade_result.to_s
    # puts trade_result
    # puts commission
    # puts ownCoin

    # sleep (5)
end

puts "trade_result:" + trade_result.to_s
