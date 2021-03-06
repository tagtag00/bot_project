#!/home/vagrant/.rbenv/shims/ruby

require 'uri'
require 'net/http'
require 'time'
require 'securerandom'
require 'base64'
require 'json'
require 'mysql2'
require 'date'

API_KEY = ENV['bfkey']
API_SECRET = ENV['bfsecret']

product_code = 'FX_BTC_JPY'
# BTC_JPY:ビットコイン現物
# FX_BTC_JPY:ビットコインFX

client = Mysql2::Client.new(
  :host => "localhost",
  :username => "root",
  :password => "taguri",
  :database => "bot_db"
)

ORDER_ON = 0
ORDER_OFF = 1

STOP_ORDER_ON = false
STOP_ORDER_OFF = true

PROFIT_ORDER_ON = false
PROFIT_ORDER_OFF = true

ORDER_DERECTION_BUY = 0
ORDER_DERECTION_SELL = 1
ORDER_DERECTION_NONE = 2

RSI_SIGNAL_BUY = 0
RSI_SIGNAL_SELL = 1
RSI_SIGNAL_STAY = 2

MACD_SIGNAL_BUY = 0
MACD_SIGNAL_SELL = 1
MACD_SIGNAL_STAY = 2

BOLLIBAN_SIGNAL_BUY = 0
BOLLIBAN_SIGNAL_SELL = 1
BOLLIBAN_SIGNAL_STAY = 2
BOLLIBAN_TEJIMAI_BUY = 3
BOLLIBAN_TEJIMAI_SELL = 4
BOLLIBAN_TEJIMAI = 5

BOLLIBAN_1_BUY = 1
BOLLIBAN_2_BUY = 2
BOLLIBAN_3_BUY = 3
BOLLIBAN_1_SELL = 1
BOLLIBAN_2_SELL = 2
BOLLIBAN_3_SELL = 3

BOARD_IS_NORMAL = 0
BOARD_IS_BUSY = 1
BOARD_IS_VERY_BUSY = 2
BOARD_IS_SUPER_BUSY = 3
BOARD_IS_NO_ORDER = 4
BOARD_IS_STOP = 5

maxCoin = 0.04
tradingUnit = 0.02

stop_price = 15
profit_price = 20

interval = 1

client.query("DELETE FROM trade_data_coll")

def getBoard(product_code = 'BTC_JPY')

    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/getboard"
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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT 3")

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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT #{range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT #{range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT #{range + range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT #{range + priRange}")

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

        for i in priRange..res.length - 2 

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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT 1")

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

    value[0] = result[0]['value'] - result[0]['signal']
    value[1] = result[1]['value'] - result[1]['signal']
    value[2] = result[2]['value'] - result[2]['signal']

    if value[0] > 0 && value[1] < 0 
        trade = "sale"
    elsif value[0] < 0 && value[1] > 0
        trade = "buy"
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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT #{range + priRange}")

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

    results = client.query("SELECT * FROM tick_data_coll ORDER BY id DESC LIMIT #{range + priRange}")

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
    mid_value = []
    trigger = "stay"

    value[0] = bollingerBand(range, 0)
    value[1] = bollingerBand(range, 1)
    value[2] = bollingerBand(range, 2)
    value[3] = bollingerBand(range, 3)

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

        mid_value[0] = value[0]['midband'] - value[1]['midband']
        mid_value[1] = value[1]['midband'] - value[2]['midband']

        row = (value[3]['plus3sigma'] - value[3]["minus3sigma"]) / (value[0]['plus3sigma'] - value[0]["minus3sigma"])

        # if row > 0.85 && row < 1.15
        if row > 0.85 && row < 1.15
            puts buyres[1][0]
            puts buyres[1][1]
            puts buyres[1][2]
            puts saleres[1][0]
            puts saleres[1][1]
            puts saleres[1][2]
            if buyres[2][0] > 0 && buyres[2][1] < 0 && buyres[2][2] < 0 then
                trigger = "buy"
            elsif buyres[1][0] > 0 && buyres[1][1] < 0 && buyres[1][2] < 0 then
                trigger = "buy"
            # elsif buyres[0][0] > 0 && buyres[0][1] < 0 && buyres[0][2] < 0
            #     trigger = "buy"
            elsif saleres[2][0] < 0 && saleres[2][1] > 0 && saleres[2][2] > 0 then
                trigger = "sale"
            elsif saleres[1][0] < 0 && saleres[1][1] > 0 && saleres[1][2] > 0 then
                trigger = "sale"
            # elsif saleres[0][0] < 0 && saleres[0][1] < 0 && saleres[0][2] > 0
            #     trigger = "sale"
            elsif midres[0] < 0 && midres[1] > 0 && midres[2] > 0 then
                trigger = "tejimai"
            elsif midres[0] > 0 && midres[1] < 0 && midres[2] < 0 then
                trigger = "tejimai"
            end
        elsif row < 0.79
            # if saleres[1][0] < 0 && saleres[1][1] < 0 && saleres[1][2] > 0
            #     trigger = "sale"
            # # elsif saleres[0][0] > 0 && saleres[0][1] > 0 && saleres[0][2] < 0
            # #     trigger = "buy" 
            # elsif midres[0] > 0 && midres[1] > 0 && midres[2] < 0
            #     trigger = "buy"
            # elsif value[0]['nowPrice'] < value[0]['midband']
            #     trigger = "tejimai"
            # end
            # if value[0]['nowPrice'] < value[0]['midband']
            #     # if buyres[1][0] < 0 && buyres[1][1] < 0 && buyres[1][2] > 0
            #     #     trigger = "sale"
            #     # elsif buyres[2][0] < 0 && buyres[2][1] < 0 && buyres[2][2] > 0
            #     #     trigger = "sale"
            #     # elsif buyres[0][0] > 0 && buyres[0][1] > 0 && buyres[0][2] < 0
            #     #     trigger = "tejimai"
            #     # end
            #     if buyres[1][0] < 0 && buyres[1][1] < 0 && buyres[1][2] > 0
            #         trigger = "sale"
            #     # elsif buyres[2][0] > 0 && buyres[2][1] > 0 && buyres[2][2] < 0
            #     #     trigger = "sale"
            #     # elsif buyres[1][0] < 0 && buyres[1][1] < 0 && buyres[1][2] > 0
            #     #     trigger = "sale"
            #     # elsif buyres[1][0] > 0 && buyres[1][1] > 0 && buyres[1][2] < 0
            #     #     trigger = "sale"
            #     # elsif buyres[0][0] < 0 && buyres[0][1] < 0 && buyres[0][2] > 0
            #     #     trigger = "sale"                
            #     elsif buyres[0][0] > 0 && buyres[0][1] > 0 && buyres[0][2] < 0
            #         trigger = "tejimai"
            #     end
            # else
            #     # if saleres[1][0] > 0 && saleres[1][1] > 0 && saleres[1][2] < 0
            #     #     trigger = "sale"
            #     # elsif saleres[2][0] < 0 && saleres[2][1] < 0 && saleres[2][2] > 0
            #     #     trigger = "sale"
            #     # elsif saleres[0][0] < 0 && saleres[0][1] < 0 && saleres[0][2] > 0
            #     #     trigger = "tejimai"
            #     # end
            #     if saleres[1][0] > 0 && saleres[1][1] > 0 && saleres[1][2] < 0
            #         trigger = "sale"
            #     # elsif saleres[2][0] < 0 && saleres[2][1] < 0 && saleres[2][2] > 0
            #     #     trigger = "sale"
            #     # elsif saleres[1][0] > 0 && saleres[1][1] > 0 && saleres[1][2] < 0
            #     #     trigger = "sale"
            #     # elsif saleres[1][0] < 0 && saleres[1][1] < 0 && saleres[1][2] > 0
            #     #     trigger = "sale"
            #     # elsif saleres[0][0] > 0 && saleres[0][1] > 0 && saleres[0][2] < 0
            #     #     trigger = "sale"                
            #     elsif saleres[0][0] < 0 && saleres[0][1] < 0 && saleres[0][2] > 0
            #         trigger = "tejimai"
            #     end
            # end
        else

        # elsif mid_value[0] > 0 && mid_value[1] > 0
        #     if midres[0] < 0 && midres[1] > 0 && midres[2] > 0
        #         trigger = "buy"
        #     elsif saleres[1][0] < 0 && saleres[1][1] < 0 && saleres[1][2] > 0
        #         trigger = "sale"
        #     end
        # elsif mid_value[0] < 0 && mid_value[1] < 0
        #     if midres[0] > 0 && midres[1] > 0 && midres[2] < 0
        #         trigger = "sale"
        #     elsif buyres[1][0] > 0 && buyres[1][1] > 0 && buyres[1][2] < 0
        #         trigger = "buy"
        #     end
        end

        case value[0]['nowPrice']
        when value[0]['minus3sigma'] .. value[0]['minus2sigma']
            puts "BB:-3" + "   変動率:" + row.to_s
        when value[0]['minus2sigma'] .. value[0]['minus1sigma']
            puts "BB:-2" + "   変動率:" + row.to_s
        when value[0]['minus1sigma'] .. value[0]['midband']
            puts "BB:-1" + "   変動率:" + row.to_s
        when value[0]['midband'] .. value[0]['plus1sigma']
            puts "BB:+1" + "   変動率:" + row.to_s
        when value[0]['plus1sigma'] .. value[0]['plus2sigma']
            puts "BB:+2" + "   変動率:" + row.to_s
        when value[0]['plus2sigma'] .. value[0]['plus3sigma']
            puts "BB:+3" + "   変動率:" + row.to_s
        else
            puts "範囲外" + "   変動率:" + row.to_s
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
    # macdT = macdTrend()
    # bbtrigger = bollingerTrigger(105)
    # mcross = macdCross(20, 52, 9)
    # mac = macd(6,14,6)
    # macValue = mac['value'] - mac['signal']
    # mstate = maCross()
    # puts "ma disp:" + (nowMaDisp = wMovingAverage(200) - wMovingAverage(200,1)).to_s
    # puts "mstate:" + mstate = maCross()
    # trend = maTrend()
    puts rsi = relativeStrengthIndex(120, 0)
    rsi_1 = relativeStrengthIndex(120, 1)
    if rsi && rsi_1 
    else 
        rsi = 50
        rsi_1 = 50
    end
    if rsi < 65 &&  rsi_1 > 65
    # if dstate == "sale" && rsi > 50 && trend == "sale"
    # if dstate == "sale" && rsi > 52 && macValue < 0 && trend == "sale"
    # if mcross == "sale"
        trade = "sale"
    # elsif dstate == "buy" && trend == "buy" || mstate == "buy" && rsi < 30
    # elsif dstate == "buy" && trend == "buy" && rsi < 40
    # elsif dstate == "buy" && rsi < 28 && macValue > 0
    # elsif mcross == "buy"
    elsif rsi > 35 &&  rsi_1 < 35
        trade = "buy"
    else
        trade = "stay"
    end

    return trade
end

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

def getBoardstate(product_code = "BTC_JPY")

    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/getboardstate"
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

def getCollateral()

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getcollateral"
    text = timestamp + 'GET' + uri.request_uri

    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

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

def getChildorder_id(product_code, id)

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getchildorders"
    uri.query = 'product_code=' + product_code + '&child_order_acceptance_id=' + id
    text = timestamp + 'GET' + uri.request_uri

    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

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

def getCollateralAccounts()

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getcollateralaccounts"
    text = timestamp + 'GET' + uri.request_uri

    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

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

# BTC_FXの一覧の取得
def getPositions(product_code = 'FX_BTC_JPY')

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getpositions"
    uri.query = 'product_code=' + product_code
    text = timestamp + 'GET' + uri.request_uri

    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

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

# 保有BTC_FX数の取得
def getTotalPosition(product_code = 'FX_BTC_JPY')

    position_results = getPositions()
    position_total = 0

    if position_results != false
        position_results.each do |rows|
            if rows['side'] == "BUY"
                position_total += rows['size']
            elsif rows['side'] == "SELL"
                position_total -= rows['size']
            end
        end
    else
        return false
    end

    return position_total
end

def getChildOrders(product_code = 'BTC_JPY')

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getchildorders"
    uri.query = 'product_code=' + product_code + '&child_order_state=ACTIVE'
    text = timestamp + 'GET' + uri.request_uri

    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

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

# 通常注文
def order(product_code = "BTC_JPY", order_type = "MARKET", price = 0, size, buy_sell)

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/sendchildorder"

    body = '{
        "product_code" : "' + product_code + '",
        "child_order_type" : "' + order_type + '",
        "side" : "' + buy_sell + '",
        "price": ' + price.to_s + ',
        "size" : ' + size.to_s + ',
        "minute_to_expire" : 10,
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
    puts result = JSON.parse(response.body)

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
        return result
    end

end

# 特殊注文 IFDOCO 買いから
def parentorder_buy(product_code = "BTC_JPY", size, reference_price, stop_price, profit_price)

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/sendparentorder"

    body = '{
        "order_method": "IFDOCO",
        "minute_to_expire" : 3,
        "time_in_force" : "GTC",
        "parameters": [{
            "product_code" : "' + product_code + '",
            "condition_type": "LIMIT",
            "side": "BUY",
            "price": ' + reference_price.to_s + ',  
            "size": ' + size.to_s + '
        },{
            "product_code" : "' + product_code + '",
            "condition_type": "LIMIT",
            "side": "SELL",
            "price": ' + stop_price.to_s + ',
            "size": ' + size.to_s + '
        },{
            "product_code" : "' + product_code + '",
            "condition_type": "LIMIT",
            "side": "SELL",
            "price" : ' + profit_price.to_s + ',
            "size": ' + size.to_s + '
        }]
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
    puts result = JSON.parse(response.body)

    # if (result['status'] == -201) then
    #     puts ' ' + product_code + " You have reached the maximum amount of trades for your account class."
    #     return false
    # end
    # if (result['parent_order_acceptance_id'] == nil) then
    #     puts ' ' + product_code + " Insufficient funds"
    #     return false
    # end 
    # if (result['parent_order_acceptance_id'] != nil) then
    #     puts ' ' + product_code + " id:" + result['parent_order_acceptance_id'] + " size:" + size.to_s
    # end

    return true
end

# 特殊注文 IFDOCO 売りから
def parentorder_sell(product_code = "BTC_JPY", size, reference_price, stop_price, profit_price)

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/sendparentorder"

    body = '{
        "order_method": "IFDOCO",
        "minute_to_expire" : 3,
        "time_in_force" : "GTC",
        "parameters": [{
            "product_code" : "' + product_code + '",
            "condition_type": "LIMIT",
            "side": "SELL",
            "price": ' + reference_price.to_s + ',  
            "size": ' + size.to_s + '
        },
        {
            "product_code" : "' + product_code + '",
            "condition_type": "LIMIT",
            "side": "BUY",
            "price": '+ stop_price.to_s + ',
            "size": ' + size.to_s + '
        },{
            "product_code" : "' + product_code + '",
            "condition_type": "LIMIT",
            "side": "BUY",
            "price": ' + profit_price.to_s + ',
            "size": ' + size.to_s + '
        }]
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
    puts result = JSON.parse(response.body)

    # if (result['status'] == -201) then
    #     puts ' ' + product_code + " You have reached the maximum amount of trades for your account class."
    #     return false
    # end
    # if (result['parent_order_acceptance_id'] == nil) then
    #     puts ' ' + product_code + " Insufficient funds"
    #     return false
    # end 
    # if (result['parent_order_acceptance_id'] != nil) then
    #     puts ' ' + product_code + " id:" + result['parent_order_acceptance_id'] + " size:" + size.to_s
    # end

    return true
end

# 手仕舞いオーダー
def stop_order(product_code = "BTC_JPY", order_type = "MARKET", price = 0, size)

    if size > 0
        result = order(product_code, order_type, price, size.abs, "SELL",)
    elsif size < 0
        result = order(product_code, order_type, price, size.abs, "BUY",)
    end

    return result
end

def childorder_cancel(product_code = "BTC_JPY", child_order_id)
    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/cancelchildorder"

    body = '{
        "product_code": "' + product_code + '",
        "child_order_id": "' + child_order_id + '"
    }'

    text = timestamp + 'POST' + uri.request_uri + body
    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Post.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

    begin
        options.body = body
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        response = https.request(options)

        case response
        when Net::HTTPSuccess
            # result = JSON.parse(response.body)
            return true
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

def parentorder_cancel(product_code = "BTC_JPY", parent_order_id)
    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/cancelparentorder"

    body = '{
        "product_code": "' + product_code + '",
        "parent_order_id": "' + parent_order_id + '"
    }'

    text = timestamp + 'POST' + uri.request_uri + body
    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Post.new(uri.request_uri, initheader = {
        "ACCESS-KEY" => API_KEY,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
        "Content-Type" => "application/json"
    });

    begin
        options.body = body
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        response = https.request(options)

        case response
        when Net::HTTPSuccess
            # result = JSON.parse(response.body)
            return true
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


ownFxCoin = 0

order_list = []

# 現在の保有BFX数の取得
total_position = getTotalPosition()
while total_position == false
    sleep(1)
    total_position = getTotalPosition()
end
ownFxCoin = total_position

stop_order_status = STOP_ORDER_OFF
profit_order_status = PROFIT_ORDER_OFF
rsi_status = RSI_SIGNAL_STAY
macd_status = MACD_SIGNAL_STAY
bolliban_status = BOLLIBAN_SIGNAL_STAY
order_derection_status = ORDER_DERECTION_NONE
order_status = ORDER_OFF

order_derection_wait_count = 0
stop_order_size = 0
order_wait_count = 0

stop_order_id = false
profit_order_id = false
order_id = false

loop do

    order_result = true

    # 現在の保有BFX数の取得
    total_position = getTotalPosition()
    while total_position == false
        sleep(1)
        total_position = getTotalPosition()
    end

    # 市場の取引状態の取得
    boardstate = getBoardstate(product_code)
    while boardstate == false
        sleep(1)
        boardstate = getBoardstate(product_code)
    end
    case boardstate["health"]
    when "NORMAL"
        board_status = BOARD_IS_NORMAL
    when "BUSY"
        board_status = BOARD_IS_BUSY
    when "VERY BUSY"
        board_status = BOARD_IS_VERY_BUSY
    when "SUPER BUSY"
        board_status = BOARD_IS_SUPER_BUSY
    when "NO ORDER"
        board_status = BOARD_IS_NO_ORDER
    when "STOP"
        board_status = BOARD_IS_STOP        
    end

    # 現在の評価損益の取得
    total_collateral = getCollateral()
    while total_collateral == false
        sleep(1)
        total_collateral = getCollateral()
    end

    # 現在のレートの取得
    result = getBoard(product_code)
    while result == false
        sleep(1)
        result = getBoard(product_code)
    end
    now_price = result['mid_price']

    # 現在時刻の取得
    time = Time.new

    puts "現在時刻:" + time.to_s()
    puts "BTCFX :" + total_position.to_s + "  評価損益 :" + total_collateral['open_position_pnl'].to_s
    puts "現在の価格 :" + now_price.to_s + " 市場状態:" + boardstate["health"]
    # データベースへの登録
    client.query("INSERT INTO tick_data_coll (timestamp, price) VALUES ('#{time}','#{now_price}')")

    # RSIの取得＆シグナル判定 
    # rsi_value = relativeStrengthIndex(14, 0)

    # case rsi_value
    # when 0..40 then
    #     rsi_status = RSI_SIGNAL_BUY
    # when 60..100 then
    #     rsi_status = RSI_SIGNAL_SELL
    # else
    #     rsi_status = RSI_SIGNAL_STAY
    # end

    # puts "RSI:" + rsi_value.to_s + "  RSI_STATUS:" + rsi_status.to_s

    # MACDのクロス判定
    # resalut = macdCross(12, 26, 9)
    # case resalut
    # when "sale" then
    #     macd_status = MACD_SIGNAL_SELL
    # when "buy" then
    #     macd_status = MACD_SIGNAL_BUY
    # else
    #     macd_status = MACD_SIGNAL_STAY        
    # end
    # puts "MACD CROSS:" + macd_status.to_s

    # macdT = macdTrend()

    # ボリンジャーバンドの取得
    resalut = bollingerTrigger(100)

    # if macdT == "sale" && resalut == "sale"
    #     flag = "sale"
    # elsif macdT == "buy" && resalut == "buy"
    #     flag = "buy"
    # elsif resalut == "tejimai"
    #     flag = "tejimai"
    # end

    case resalut
    when "sale" then
        bolliban_status = BOLLIBAN_SIGNAL_SELL
    when "buy" then
        bolliban_status = BOLLIBAN_SIGNAL_BUY
    when "tejimai" then
        bolliban_status = BOLLIBAN_TEJIMAI
        puts "手仕舞いします"
    else
        bolliban_status = BOLLIBAN_SIGNAL_STAY       
    end    

    # puts "BOLLIBAN TRIGGER:" + bolliban_status.to_s
    # 売買判定
    # if macd_status == MACD_SIGNAL_BUY && rsi_status == RSI_SIGNAL_BUY
    if bolliban_status == BOLLIBAN_SIGNAL_BUY
        puts "買います"
        trade = "buy"
    # elsif macd_status == MACD_SIGNAL_SELL && rsi_status == RSI_SIGNAL_SELL
    elsif bolliban_status == BOLLIBAN_SIGNAL_SELL
        puts "売ります"
        trade = "sale"
    end

    # puts order_list
    # ポジションを持っている場合の処理
    # if ownFxCoin.abs > 0
    # child_results = getChildOrders(product_code)

    if stop_order_status == STOP_ORDER_OFF
        puts "手仕舞い判定"
        # STOP ODER
        if total_collateral['open_position_pnl'] < (stop_price * -1) || bolliban_status == BOLLIBAN_TEJIMAI && total_position.abs > 0.001

            # 未成立取引のキャンセル
            puts child_results = getChildOrders(product_code)

            child_results.each do |rows|
                childorder_cancel(product_code, rows['child_order_id'])
            end

            # 最低発注単位調整
            orderSize = BigDecimal(total_position.to_s).floor(3).to_f

            # 手仕舞い
            order_result = stop_order(product_code, "MARKET", 0, orderSize)

            while order_result == false
                sleep(1)
                order_result = stop_order(product_code, "MARKET", 0, orderSize)
            end

            stop_order_id = order_result["child_order_acceptance_id"]

            order_status = ORDER_OFF

            puts "損切り"

            ownFxCoin = 0

            stop_order_status = STOP_ORDER_ON
            order_derection_status = ORDER_DERECTION_NONE

        elsif total_collateral['open_position_pnl'] > profit_price && profit_order_status == PROFIT_ORDER_OFF

            # 未成立取引のキャンセル
            puts child_results = getChildOrders(product_code)

            child_results.each do |rows|
                childorder_cancel(product_code, rows['child_order_id'])
            end

            # 最低発注単位調整
            orderSize = BigDecimal(total_position.to_s).floor(3).to_f
            
            # 手仕舞い価格の決定
            if orderSize > 0
                order_price = now_price - 95
            elsif orderSize < 0
                order_price = now_price + 95
            end

            # 手仕舞い
            order_result = stop_order(product_code, "LIMIT", order_price, orderSize)

            while order_result == false
                sleep(1)
                order_result = stop_order(product_code, "LIMIT", order_price, orderSize)
            end

            profit_order_id = order_result["child_order_acceptance_id"]

            puts "利確"

            ownFxCoin = 0

            profit_order_status = PROFIT_ORDER_ON
            order_derection_status = ORDER_DERECTION_NONE
            order_status = ORDER_OFF

        end

        # 新規ポジション
        if total_position.abs < maxCoin && stop_order_status == STOP_ORDER_OFF && profit_order_status == PROFIT_ORDER_OFF && board_status < BOARD_IS_BUSY && order_status == ORDER_OFF
            puts "売買判定"
            # puts "trade:" + trade = getTradeState()

            case trade
            when 'sale' then
                if order_derection_status != ORDER_DERECTION_BUY
                    # オーダーのデーターベース登録
                    query = "INSERT INTO trade_data_coll (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{total_position}','#{result['ltp']}',0)"
                    client.query(query)

                    # オーダー
                    order_result = order(product_code, "LIMIT", now_price - 95, tradingUnit, "SELL")

                    while order_result == false
                        sleep(1)
                        order_result = order(product_code, "LIMIT", now_price - 95, tradingUnit, "SELL")
                    end

                    order_id = order_result["child_order_acceptance_id"]

                    order_derection_status = ORDER_DERECTION_SELL
                    ownFxCoin -= tradingUnit

                    order_status = ORDER_ON
                else
                    # 未成立取引のキャンセル
                    puts child_results = getChildOrders(product_code)

                    child_results.each do |rows|
                        childorder_cancel(product_code, rows['child_order_id'])
                    end

                    # 最低発注単位調整
                    orderSize = BigDecimal(total_position.to_s).floor(3).to_f
                    
                    # 手仕舞い価格の決定
                    if orderSize < 0
                        order_price = now_price + 95
                        ownFxCoin = 0
                        profit_order_status = PROFIT_ORDER_ON
                        puts "手仕舞い"
                    elsif orderSize > 0
                        order_price = now_price - 95
                        ownFxCoin = 0
                        profit_order_status = PROFIT_ORDER_ON
                        puts "手仕舞い"
                    elsif orderSize == 0
                        order_price = now_price
                        orderSize = tradingUnit
                        ownFxCoin -= tradingUnit
                        profit_order_status = PROFIT_ORDER_OFF
                        puts "逆方向"
                    end

                    # 手仕舞い
                    puts order_result = stop_order(product_code, "LIMIT", order_price, orderSize)

                    while order_result == false
                        sleep(1)
                        puts order_result = stop_order(product_code, "LIMIT", order_price, orderSize)
                    end

                    order_id = order_result["child_order_acceptance_id"]

                    # puts "手仕舞い"

                end

            when 'buy' then
                if order_derection_status != ORDER_DERECTION_SELL
                    # オーダーのデーターベース登録
                    query = "INSERT INTO trade_data_coll (timestamp, tradeType, tradeNum, price, total) VALUES ('#{time}','#{trade}','#{tradingUnit}','#{result['ltp']}','#{total_position}')"
                    client.query(query)

                    # オーダー
                    order_result = order(product_code, "LIMIT", now_price + 95, tradingUnit, "BUY")

                    while order_result == false
                        sleep(1)
                        order_result = order(product_code, "LIMIT", now_price + 95, tradingUnit, "BUY")
                    end

                    order_id = order_result["child_order_acceptance_id"]

                    order_derection_status = ORDER_DERECTION_BUY
                    ownFxCoin += tradingUnit

                    order_status = ORDER_ON
                else
                    # 未成立取引のキャンセル
                    puts child_results = getChildOrders(product_code)

                    child_results.each do |rows|
                        childorder_cancel(product_code, rows['child_order_id'])
                    end

                    # 最低発注単位調整
                    orderSize = BigDecimal(total_position.to_s).floor(3).to_f
                    
                    # 手仕舞い価格の決定
                    if orderSize < 0
                        order_price = now_price + 95
                        ownFxCoin = 0
                        profit_order_status = PROFIT_ORDER_ON
                        puts "手仕舞い"
                    elsif orderSize > 0
                        order_price = now_price - 95
                        ownFxCoin = 0
                        profit_order_status = PROFIT_ORDER_ON
                        puts "手仕舞い"
                    elsif orderSize == 0
                        order_price = now_price
                        orderSize = tradingUnit * -1
                        ownFxCoin += tradingUnit
                        profit_order_status = PROFIT_ORDER_OFF
                        puts "逆方向"
                    end

                    # 手仕舞い
                    puts order_result = stop_order(product_code, "LIMIT", order_price, orderSize)

                    while order_result == false
                        sleep(1)
                        puts order_result = stop_order(product_code, "LIMIT", order_price, orderSize)
                    end

                    order_id = order_result["child_order_acceptance_id"]

                    # puts "手仕舞い"

                    # order_derection_status = ORDER_DERECTION_BUY

                end
            end
        end
    end

    # 長時間動きがない場合はリセット
    if order_derection_status != ORDER_DERECTION_NONE
        if order_derection_wait_count < 60
            order_derection_wait_count += 1
        else
            # 未成立取引のキャンセル
            puts "動きがない"
            # puts child_results = getChildOrders(product_code)

            # child_results.each do |rows|
            #     childorder_cancel(product_code, rows['child_order_id'])
            # end
            order_derection_wait_count = 0

            order_derection_status = ORDER_DERECTION_NONE
            profit_order_status = PROFIT_ORDER_OFF

            if total_collateral['open_position_pnl'].abs <= 0.009 
                ownFxCoin = 0
            end
        end
    end

    # オーダーの約定確認
    if order_id != false
        puts result = getChildorder_id(product_code, order_id)
        result.each do |row|
            if row["child_order_state"] == "COMPLETED"
                if row['side'] == "SELL"
                    order_price = row['price'] - 595

                    order_result = order(product_code, "LIMIT", order_price, tradingUnit, "BUY")

                    while order_result == false
                        sleep(1)
                        order_result = order(product_code, "LIMIT", order_price, tradingUnit, "BUY")
                    end                    
                else
                    order_price = row['price'] + 595

                    order_result = order(product_code, "LIMIT", order_price, tradingUnit, "SELL")

                    while order_result == false
                        sleep(1)
                        order_result = order(product_code, "LIMIT", order_price, tradingUnit, "SELL")
                    end
                end

                order_status = ORDER_OFF
                profit_order_status = PROFIT_ORDER_OFF
                order_id = false

            elsif order_wait_count < 10

                order_wait_count += 1

            else
                # 未成立取引のキャンセル
                puts "約定未成立"
                puts child_results = getChildOrders(product_code)

                child_results.each do |rows|
                    childorder_cancel(product_code, rows['child_order_id'])
                end

                order_wait_count = 0

                order_derection_status = ORDER_DERECTION_NONE
                profit_order_status = PROFIT_ORDER_OFF
                order_status = ORDER_OFF
                order_id = false

                if total_collateral['open_position_pnl'].abs <= 0.009 
                    ownFxCoin = 0
                end
            end
        end
    end

    # 損切りオーダーの約定確認
    if stop_order_id != false
        puts result = getChildorder_id(product_code, stop_order_id)
        result.each do |row|
            if row["child_order_state"] == "COMPLETED"
                stop_order_status = STOP_ORDER_OFF
                stop_order_id = false
            end
        end
    end

    # 利確オーダーの約定確認
    if profit_order_id != false
        puts result = getChildorder_id(product_code, profit_order_id)
        result.each do |row|
            if row["child_order_state"] == "COMPLETED"
                profit_order_status = PROFIT_ORDER_OFF
                profit_order_id = false
            end
        end
    end

    puts "profit_order_status:" + profit_order_status.to_s
    puts "stop_order_status:" + stop_order_status.to_s
    puts "order_status:" + order_status.to_s
    puts "order_derection_status:" + order_derection_status.to_s

    sleep (interval)
end


