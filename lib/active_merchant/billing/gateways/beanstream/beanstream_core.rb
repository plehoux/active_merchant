module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    module BeanstreamCore
      URL = 'https://www.beanstream.com/scripts/process_transaction.asp'
      RECURRING_URL = 'https://www.beanstream.com/scripts/recurring_billing.asp'
      SECURE_PROFILE_URL = 'https://www.beanstream.com/scripts/payment_profile.asp'
      SP_SERVICE_VERSION = '1.1'

      TRANSACTIONS = {
        :authorization  => 'PA',
        :purchase       => 'P',
        :capture        => 'PAC',
        :refund         => 'R',
        :void           => 'VP',
        :check_purchase => 'D',
        :check_refund   => 'C',
        :void_purchase  => 'VP',
        :void_refund    => 'VR'
      }

      PROFILE_OPERATIONS = {
        :new => 'N',
        :modify => 'M'
      }

      CVD_CODES = {
        '1' => 'M',
        '2' => 'N',
        '3' => 'I',
        '4' => 'S',
        '5' => 'U',
        '6' => 'P'
      }

      AVS_CODES = {
        '0' => 'R',
        '5' => 'I',
        '9' => 'I'
      }

      PERIOD = {
        :days => 'D',
        :weeks => 'W',
        :months => 'M',
        :years => 'Y'
      }
      
      def self.included(base)
        base.default_currency = 'CAD'

        # The countries the gateway supports merchants from as 2 digit ISO country codes
        base.supported_countries = ['CA']

        # The card types supported by the payment gateway
        base.supported_cardtypes = [:visa, :master, :american_express]

        # The homepage URL of the gateway
        base.homepage_url = 'http://www.beanstream.com/'

        # The name of the gateway
        base.display_name = 'Beanstream.com'
      end
      
      # Only <tt>:login</tt> is required by default, 
      # which is the merchant's merchant ID. If you'd like to perform void, 
      # capture or refund transactions then you'll also need to add a username
      # and password to your account under administration -> account settings ->
      # order settings -> Use username/password validation
      def initialize(options = {})
        requires!(options, :login)
        @options = options
        super
      end
      
      def capture(money, authorization, options = {})
        reference, amount, type = split_auth(authorization)
        
        post = {}
        add_amount(post, money)
        add_reference(post, reference)
        add_transaction_type(post, :capture)
        commit(post)
      end
      
      def refund(money, source, options = {})
        post = {}
        reference, amount, type = split_auth(source)
        add_reference(post, reference)
        add_transaction_type(post, refund_action(type))
        add_amount(post, money)
        commit(post)
      end

      def credit(money, source, options = {})
        deprecated Gateway::CREDIT_DEPRECATION_MESSAGE
        refund(money, source, options)
      end
    
      private
      def purchase_action(source)
        if source.is_a?(Check)
          :check_purchase
        else
          :purchase
        end
      end
      
      def void_action(original_transaction_type)
        (original_transaction_type == TRANSACTIONS[:refund]) ? :void_refund : :void_purchase
      end
      
      def refund_action(type)
        (type == TRANSACTIONS[:check_purchase]) ? :check_refund : :refund
      end
      
      def secure_profile_action(type)
        PROFILE_OPERATIONS[type] || PROFILE_OPERATIONS[:new]
      end
      
      def split_auth(string)
        string.split(";")
      end
      
      def add_amount(post, money)
        post[:trnAmount] = amount(money)
      end
      
      def add_original_amount(post, amount)
        post[:trnAmount] = amount
      end

      def add_reference(post, reference)                
        post[:adjId] = reference
      end
      
      def add_address(post, options)
        prepare_address_for_non_american_countries(options)
        
        if billing_address = options[:billing_address] || options[:address]
          post[:ordName]          = billing_address[:name]
          post[:ordEmailAddress]  = options[:email]
          post[:ordPhoneNumber]   = billing_address[:phone]
          post[:ordAddress1]      = billing_address[:address1]
          post[:ordAddress2]      = billing_address[:address2]
          post[:ordCity]          = billing_address[:city]
          post[:ordProvince]      = billing_address[:state]
          post[:ordPostalCode]    = billing_address[:zip]
          post[:ordCountry]       = billing_address[:country]
        end
        if shipping_address = options[:shipping_address]
          post[:shipName]         = shipping_address[:name]
          post[:shipEmailAddress] = options[:email]
          post[:shipPhoneNumber]  = shipping_address[:phone]
          post[:shipAddress1]     = shipping_address[:address1]
          post[:shipAddress2]     = shipping_address[:address2]
          post[:shipCity]         = shipping_address[:city]
          post[:shipProvince]     = shipping_address[:state]
          post[:shipPostalCode]   = shipping_address[:zip]
          post[:shipCountry]      = shipping_address[:country]
          post[:shippingMethod]   = shipping_address[:shipping_method]
          post[:deliveryEstimate] = shipping_address[:delivery_estimate]
        end
      end

      def prepare_address_for_non_american_countries(options)
        [ options[:billing_address], options[:shipping_address] ].compact.each do |address|
          unless ['US', 'CA'].include?(address[:country])
            address[:state] = '--'
            address[:zip]   = '000000' unless address[:zip]
          end
        end
      end

      def add_invoice(post, options)
        post[:trnOrderNumber]   = options[:order_id]
        post[:trnComments]      = options[:description]
        post[:ordItemPrice]     = amount(options[:subtotal])
        post[:ordShippingPrice] = amount(options[:shipping])
        post[:ordTax1Price]     = amount(options[:tax1] || options[:tax])
        post[:ordTax2Price]     = amount(options[:tax2])
        post[:ref1]             = options[:custom]
      end
      
      def add_credit_card(post, credit_card)
        if credit_card
          post[:trnCardOwner] = credit_card.name
          post[:trnCardNumber] = credit_card.number
          post[:trnExpMonth] = format(credit_card.month, :two_digits)
          post[:trnExpYear] = format(credit_card.year, :two_digits)
          post[:trnCardCvd] = credit_card.verification_value
        end
      end
            
      def add_check(post, check)
        # The institution number of the consumer’s financial institution. Required for Canadian dollar EFT transactions.
        post[:institutionNumber] = check.institution_number
        
        # The bank transit number of the consumer’s bank account. Required for Canadian dollar EFT transactions.
        post[:transitNumber] = check.transit_number
        
        # The routing number of the consumer’s bank account.  Required for US dollar EFT transactions.
        post[:routingNumber] = check.routing_number
        
        # The account number of the consumer’s bank account.  Required for both Canadian and US dollar EFT transactions.
        post[:accountNumber] = check.account_number
      end
      
      def add_recurring_amount(post, money)
        post[:amount] = amount(money)
      end
      
      def add_recurring_invoice(post, options)
        post[:rbApplyTax1] = options[:apply_tax1]
      end
      
      def add_recurring_operation_type(post, operation)
        post[:operationType] = if operation == :update
                                 'M'
                               elsif operation == :cancel
                                 'C'
                               end
      end
      
      def add_recurring_service(post, options)
        post[:serviceVersion] = '1.0'
        post[:merchantId]     = @options[:login]
        post[:passCode]       = @options[:pass_code]
        post[:rbAccountId]    = options[:account_id]
      end
      
      def add_recurring_type(post, options)
        recurring_options         = options[:recurring_billing]
        post[:trnRecurring]       = '1'
        post[:rbBillingPeriod]    = PERIOD[recurring_options[:interval][:unit]]
        post[:rbBillingIncrement] = recurring_options[:interval][:length]
        post[:rbFirstBilling]     = recurring_options[:duration][:start_date].strftime("%m%d%Y")
        post[:rbExpiry]           = (recurring_options[:duration][:start_date] >> recurring_options[:duration][:occurrences]).strftime("%m%d%Y") if !recurring_options[:duration][:occurrences].nil?
        post[:rbEndMonth]         = recurring_options[:end_of_month] if recurring_options[:end_of_month]
        post[:rbApplyTax1]        = recurring_options[:tax1] if recurring_options[:tax1]
      end
      
      def add_secure_profile_variables(post, options = {})
        post[:serviceVersion] = SP_SERVICE_VERSION
        post[:responseFormat] = 'QS'
        post[:cardValidation] = (options[:cardValidation].to_i == 1) || '0'
        
        post[:operationType] = options[:operationType] || options[:operation] || secure_profile_action(:new)
        post[:customerCode] = options[:billing_id] || options[:vault_id] || false
        post[:status] = options[:status]
      end
      
      def parse(body)
        results = {}
        if !body.nil?
          body.split(/&/).each do |pair|
            key,val = pair.split(/=/) #/
            results[key.to_sym] = val.nil? ? nil : CGI.unescape(val)
          end
        end
        
        # Clean up the message text if there is any
        if results[:messageText]
          results[:messageText].gsub!(/<LI>/, "")
          results[:messageText].gsub!(/(\.)?<br>/, ". ")
          results[:messageText].strip!
        end
        
        results
      end
      

      def recurring_parse(data)
        response = {}
        xml = REXML::Document.new(data)
        root = REXML::XPath.first(xml, "response")
        
        root.elements.to_a.each do |node|
          recurring_parse_element(response, node)
        end
        
        response
      end
      
      def recurring_parse_element(response, node)
        if node.has_elements?
          node.elements.each{|e| recurring_parse_element(response, e) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end
      
      def recurring_commit(params, use_profile_api = false)
        recurring_post(post_data(params,use_profile_api))
      end
      
      def commit(params, use_profile_api = false)
        post(post_data(params,use_profile_api),use_profile_api)
      end
      
      def post(data, use_profile_api=nil)
        response = parse(ssl_post((use_profile_api ? SECURE_PROFILE_URL : URL), data))
        response[:customer_vault_id] = response[:customerCode] if response[:customerCode]

        build_response(success?(response), message_from(response), response,
          :test => test? || response[:authCode] == "TEST",
          :authorization => authorization_from(response),
          :cvv_result => CVD_CODES[response[:cvdId]],
          :avs_result => { :code => (AVS_CODES.include? response[:avsId]) ? AVS_CODES[response[:avsId]] : response[:avsId] }
        )
      end
      
      def recurring_post(data)
        response = recurring_parse(ssl_post(RECURRING_URL, data))
        build_response(recurring_success?(response), recurring_message_from(response), response,
          :test => test? || response[:authCode] == "TEST",
          :authorization => recurring_authorization_from(response),
          :cvv_result => CVD_CODES[response[:cvdId]],
          :avs_result => { :code => (AVS_CODES.include? response[:avsId]) ? AVS_CODES[response[:avsId]] : response[:avsId] }
        )
      end
      
      def authorization_from(response)
        "#{response[:trnId]};#{response[:trnAmount]};#{response[:trnType]}"
      end
      
      def recurring_authorization_from(response)
        response[:account_id]
      end
      
      def message_from(response)
        response[:messageText] || response[:responseMessage]
      end
      
      def recurring_message_from(response)
        response[:message]
      end
      
      def success?(response)
        response[:responseType] == 'R' || response[:trnApproved] == '1' || response[:responseCode] == '1'
      end
      
      def recurring_success?(response)
        response[:code] == '1'
      end
      
      def add_source(post, source)
        if source.is_a?(String) or source.is_a?(Integer)
          post[:customerCode] = source
        else
          card_brand(source) == "check" ? add_check(post, source) : add_credit_card(post, source)
        end
      end
      
      def add_transaction_type(post, action)
        post[:trnType] = TRANSACTIONS[action]
      end
          
      def post_data(params, use_profile_api)
        params[:requestType] = 'BACKEND'
        if use_profile_api
          params[:merchantId] = @options[:login] 
          params[:passCode] = @options[:secure_profile_api_key]
        else
          params[:username] = @options[:user] if @options[:user]
          params[:password] = @options[:password] if @options[:password]
          params[:merchant_id] = @options[:login]     
        end
        params[:vbvEnabled] = '0'
        params[:scEnabled] = '0'
        
        params.reject{|k, v| v.blank?}.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end
    end
  end
end

