# = セッションIDの付与

module ActionController
  class Base #:nodoc:
    class_inheritable_accessor :trans_sid_mode

    def transit_sid_mode(*args)
      STDERR.puts "Method transit_sid is now deprecated. Use trans_sid instead."
      trans_sid_mode(*args)
    end

    class << self
      # 2.3.x or higher
      def trans_sid(mode = :mobile)
        include Jpmobile::TransSid
        self.trans_sid_mode = mode
      end

      def transit_sid(*args)
        STDERR.puts "Method transit_sid is now deprecated. Use trans_sid instead."
        trans_sid(*args)
      end
    end
  end
end

module Jpmobile::TransSid #:nodoc:
  def self.included(controller)
    controller.after_filter(:append_session_id_parameter)
  end

  protected
  # URLにsession_idを追加する。
  def default_url_options(options=nil)
    result = super || {}
    return result unless request # for test process
    return result unless apply_trans_sid?
    return result.merge({ session_key => jpmobile_session_id })
  end

  private
  # session_keyを返す。
  def session_key
    (request.session_options || ActionController::Base.session_options)[:key]
  end
  # session_idを返す
  def jpmobile_session_id
    session.session_id
  end
  # session_idを埋め込むためのhidden fieldを出力する。
  def sid_hidden_field_tag
    "<input type=\"hidden\" name=\"#{CGI::escapeHTML session_key}\" value=\"#{CGI::escapeHTML jpmobile_session_id}\" />"
  end
  # formにsession_idを追加する。
  def append_session_id_parameter
    return unless request # for test process
    return unless apply_trans_sid?
    response.body.gsub!(%r{(</form>)}i, sid_hidden_field_tag+'\1')
  end
  # trans_sidを適用すべきかを返す。
  def apply_trans_sid?
    return false if trans_sid_mode == :none
    return true if trans_sid_mode == :always
    if trans_sid_mode == :mobile
      if request.mobile?
        return !request.mobile.supports_cookie?
      else
        return false
      end
    end
    return false
  end
end
