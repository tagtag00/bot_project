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

ODER_OFF = 1
ODER_ON = 0

client = Mysql2::Client.new(
  :host => "localhost",
  :username => "root",
  :password => "taguri",
  :database => "bot_db"
)

maxCoin = 0.08
tradingUnit = 0.1

stop_limit = 1500
profit_limit = 1500 
price_interval = 1000

interval = 1

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

def getparentorders(product_code = 'BTC_JPY')

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/getparentorders"
    uri.query = 'product_code=' + product_code + '&parent_order_state=ACTIVE'
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

def getCollateral(coin_name = "JPY")

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
            return result.find {|n| n["currency_code"] == coin_name}
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

def getCollateralAccounts(coin_name = "JPY")

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
            return result.find {|n| n["currency_code"] == coin_name}
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

def getTotalPosition(product_code = 'FX_BTC_JPY')

    position_results = getPositions()
    position_total = 0

    position_results.each do |rows|
        if rows['side'] == "BUY"
            position_total += rows['size']
        elsif rows['side'] == "SELL"
            position_total -= rows['size']
        end
    end

    return position_total
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

    puts text = timestamp + 'POST' + uri.request_uri + body
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

def parentorder_buy(product_code = "BTC_JPY", size, reference_price, reference_trigger_price, stop_price, profit_price)

    price_1 = reference_price - stop_price
    # price_1_trigger = reference_price - stop_price * 0.9
    price_2 = reference_price + profit_price
    # price_2_trigger = reference_price + profit_price * 0.9

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/sendparentorder"

    body = '{
        "order_method": "IFDOCO",
        "minute_to_expire" : 1000,
        "time_in_force" : "GTC",
        "parameters": [{
            "product_code" : "' + product_code + '",
            "condition_type": "STOP_LIMIT",
            "side": "BUY",
            "price": ' + reference_price.to_s + ',  
            "trigger_price": ' + reference_trigger_price.to_s + ',
            "size": ' + size.to_s + '
        },{
            "product_code" : "' + product_code + '",
            "condition_type": "STOP",
            "side": "SELL",
            "trigger_price": ' + price_1.to_s + ',
            "size": ' + size.to_s + '
        },{
            "product_code" : "' + product_code + '",
            "condition_type": "STOP_LIMIT",
            "side": "SELL",
            "price" : ' + price_2.to_s + ',
            "trigger_price": ' + price_2.to_s + ',
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
    result = JSON.parse(response.body)

    if (result['status'] == -201) then
        puts ' ' + product_code + " You have reached the maximum amount of trades for your account class."
        return false
    end
    if (result['child_order_acceptance_id'] == nil) then
        puts ' ' + product_code + " Insufficient funds"
        return false
    end 
    if (result['child_order_acceptance_id'] != nil) then
        puts ' ' + product_code + " id:" + result['child_order_acceptance_id'] + " size:" + size.to_s
    end

    return true
end

def parentorder_sell(product_code = "BTC_JPY", size, reference_price, reference_trigger_price, stop_price, profit_price)

    price_1 = reference_price + stop_price
    # price_1_trigger = reference_price + stop_price * 0.9
    price_2 = reference_price - profit_price
    # price_2_trigger = reference_price - profit_price * 0.9

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/sendparentorder"

    body = '{
        "order_method": "IFDOCO",
        "minute_to_expire" : 1000,
        "time_in_force" : "GTC",
        "parameters": [{
            "product_code" : "' + product_code + '",
            "condition_type": "STOP_LIMIT",
            "side": "SELL",
            "price": ' + reference_price.to_s + ',  
            "trigger_price": ' + reference_trigger_price.to_s + ',
            "size": ' + size.to_s + '
        },
        {
            "product_code" : "' + product_code + '",
            "condition_type": "STOP",
            "side": "BUY",
            "trigger_price": '+ price_1.to_s + ',
            "size": ' + size.to_s + '
        },{
            "product_code" : "' + product_code + '",
            "condition_type": "STOP_LIMIT",
            "side": "BUY",
            "price": ' + price_2.to_s + ',
            "trigger_price": ' + price_2.to_s + ',
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
    result = JSON.parse(response.body)

    if (result['status'] == -201) then
        puts ' ' + product_code + " You have reached the maximum amount of trades for your account class."
        return false
    end
    if (result['child_order_acceptance_id'] == nil) then
        puts ' ' + product_code + " Insufficient funds"
        return false
    end 
    if (result['child_order_acceptance_id'] != nil) then
        puts ' ' + product_code + " id:" + result['child_order_acceptance_id'] + " size:" + size.to_s
    end

    return true
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

def cancelallorder(product_code = "BTC_JPY")

    timestamp = Time.now.to_i.to_s
    uri = URI.parse("https://api.bitflyer.jp")
    uri.path = "/v1/me/cancelallchildorders"
    body = '{
        "product_code": "' + product_code + '"
    }'

    text = timestamp + 'GET' + uri.request_uri + body

    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), API_SECRET, text)
    options = Net::HTTP::Get.new(uri.request_uri, initheader = {
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

while(1)

    # cancel_result = cancelallorder(product_code)
    order_count = 0
    order_result = true

    puts "My Collateral JPY :" + getCollateralAccounts("JPY")['amount'].to_s

    result = getBoard(product_code)

    if result != false

        # time = DateTime.parse(result['timestamp']) + Rational(9,24)
        puts "nowPrice : " + result['mid_price'].to_s

        for i in 1..3

            buyrprice = result['mid_price'] + price_interval * i
            buyrprice_trigger = result['mid_price'] + price_interval * 0.9 * i

            # order_result = parentorder_buy( product_code, tradingUnit, buyrprice, buyrprice_trigger, stop_limit, profit_limit)

            sellrprice = result['mid_price'] - price_interval * i
            sellrprice_trigger = result['mid_price'] - price_interval * 0.9 * i

            # order_result = parentorder_sell( product_code, tradingUnit, sellrprice, sellrprice_trigger, stop_limit, profit_limit)

        end

    end

    sleep(interval)

    status = ODER_OFF
    sleep_count = 0

    while(1)
        time = Time.new
        puts "nowTime : " + time.to_s

        parent_results = getparentorders(product_code)
        order_count = 0

        if parent_results.length > 0
            parent_results.each do |rows|
                if rows['executed_size'] <= 0
                    puts "未成立" + rows['parent_order_id']
                    if status == ODER_ON
                        parentorder_cancel(product_code, rows['parent_order_id'])
                    end
                else
                    puts "一部" + rows['parent_order_id']
                    status = ODER_ON
                end
            end
            sleep(1)
        else
            sleep(3)
            break
        end
    end


    # puts child_results = getChildOrders(product_code)

    # child_results.each do |rows|
    #     puts childorder_cancel(product_code, rows['child_order_id'])
    # end

        # total_position = getTotalPosition()

        # if total_position > 0
        #     # order(product_code, "SELL", total_position)
        #     puts "売ります"
        # elsif total_position < 0
        #     # order(product_code, "BUY", total_position)
        #     puts "買います"
        # end

    if order_count > 0

        puts parent_results = getparentorders(product_code)

        parent_results.each do |rows|
            puts "order stop"
            parentorder_cancel(product_code, rows['parent_order_id'])
            order_count = 0
        end

        puts child_results = getChildOrders(product_code)

        child_results.each do |rows|
            childorder_cancel(product_code, rows['child_order_id'])
        end
    end

    total_position = getTotalPosition()
    orderSize = BigDecimal(total_position.to_s).floor(4).to_f

    if orderSize > 0
        puts orderSize
        order(product_code, "SELL", orderSize)
        puts "売ります"
    elsif orderSize < 0
        order(product_code, "BUY", orderSize.abs)
        puts "買います"
    end

    # end

end


