# = viewの自動切り替え
#
# Rails 2.1.0 対応 http://d.hatena.ne.jp/kusakari/20080620/1213931903
# thanks to id:kusakari
#
#:stopdoc:
# helperを追加
ActionView::Base.class_eval { include Jpmobile::Helpers }
#:startdoc:

require 'action_pack'
require 'action_view'

# ActionView::Base を拡張して携帯からのアクセスの場合に携帯向けビューを優先表示する。
# Vodafone携帯(request.mobile == Jpmobile::Mobile::Vodafone)の場合、
#   index_mobile_vodafone.rhtml
#   index_mobile_softbank.rhtml
#   index_mobile.rhtml
#   index.rhtml
# の順にテンプレートが検索される。
# BUG: 現状、上記の例では index.rhtml が存在しない場合に振り分けが行われない
# (ダミーファイルを置くことで回避可能)。

module ActionView
  if ::ActionPack::VERSION::MAJOR >=2 and ::ActionPack::VERSION::MINOR == 3
    class PathSet
      alias find_template_without_jpmobile find_template #:nodoc:
      alias initialize_without_jpmobile initialize #:nodoc:

      attr_accessor :controller

      def initialize(*args)
        if args.first.kind_of?(ActionController::Base)
          @controller = args.shift
        end
        initialize_without_jpmobile(*args)
      end

      # hook ActionView::PathSet#find_template
      def find_template(original_template_path, format = nil, html_fallback = true) #:nodoc:
        if controller and controller.kind_of?(ActionController::Base) and controller.request.mobile?
          return original_template_path if original_template_path.respond_to?(:render)
          template_path = original_template_path.sub(/^\//, '')

          template_candidates = mobile_template_candidates(controller)
          format_postfix      = format ? ".#{format}" : ""

          each do |load_path|
            template_candidates.each do |template_postfix|
              if template = load_path["#{template_path}_#{template_postfix}#{format_postfix}"]
                return template
              end
            end
          end
        end

        return find_template_without_jpmobile(original_template_path, format, html_fallback)
      end

      # collect cadidates of mobile_template
      def mobile_template_candidates(controller)
        candidates = []
        c = controller.request.mobile.class
        while c != Jpmobile::Mobile::AbstractMobile
          candidates << "mobile_"+c.to_s.split(/::/).last.downcase
          c = c.superclass
        end
        candidates << "mobile"
      end
    end
  end

  class Base #:nodoc:
    delegate :default_url_options, :to => :controller unless respond_to?(:default_url_options)

    if ::ActionPack::VERSION::MAJOR >=2 and ::ActionPack::VERSION::MINOR == 3
      # nothing to do
      def view_paths=(paths)
        @view_paths = self.class.process_view_paths(paths, controller)
      end

      def self.process_view_paths(value, controller = nil)
        if controller && controller.is_a?(ActionController::Base)
          ActionView::PathSet.new(controller, Array(value))
        else
          ActionView::PathSet.new(Array(value))
        end
      end
    elsif ::ActionPack::VERSION::MAJOR >=2 and ::ActionPack::VERSION::MINOR == 2
      ### Rails 2.2.x
      alias _pick_template_without_jpmobile _pick_template #:nodoc:
      alias render_partial_without_jpmobile render_partial #:nodoc:

      def _pick_template(template_path)
        mobile_path = mobile_template_path(template_path)
        return mobile_path.nil? ? _pick_template_without_jpmobile(template_path) :
          _pick_template_without_jpmobile(mobile_path)
      end

      def render_partial(options = {}) #:nodoc:
        case partial_path = options[:partial]
        when String, Symbol, NilClass
          mobile_path = mobile_template_path(partial_path, true)
          options = options.merge(:partial => mobile_path) if mobile_path
        end
        render_partial_without_jpmobile(options)
      end
    else
      ### Rails 2.1 or lower
      alias render_file_without_jpmobile render_file #:nodoc:
      alias render_partial_without_jpmobile render_partial #:nodoc:

      def render_file(template_path, use_full_path = true, local_assigns = {})
        mobile_path = mobile_template_path(template_path)
        return mobile_path.nil? ? render_file_without_jpmobile(template_path, use_full_path, local_assigns) :
          render_file_without_jpmobile(mobile_path, use_full_path, local_assigns)
      end

      def render_partial(partial_path, object_assigns = nil, local_assigns = {}) #:nodoc:
        mobile_path = mobile_template_path(partial_path, true) if partial_path.class === "String"
        return mobile_path.nil? ? render_partial_without_jpmobile(partial_path, object_assigns, local_assigns) :
          render_partial_without_jpmobile(mobile_path, object_assigns, local_assigns)
      end
    end

    def mobile_template_candidates
      candidates = []
      c = controller.request.mobile.class
      while c != Jpmobile::Mobile::AbstractMobile
        candidates << "mobile_"+c.to_s.split(/::/).last.downcase
        c = c.superclass
      end
      candidates << "mobile"
    end

    def mobile_template_partial mobile_path
      # ActionView::PartialTemplate#extract_partial_name_and_path の動作を模倣
      if mobile_path.include?('/')
        path = File.dirname(mobile_path)
        partial_name = File.basename(mobile_path)
      else
        path = self.controller.class.controller_path
        partial_name = mobile_path
      end
      File.join(path, "_#{partial_name}")
    end

    def mobile_path template_path, type
      "#{template_path}_#{type}"
    end

    def mobile_template_path(template_path, partial=false)
      if controller.is_a?(ActionController::Base) && m = controller.request.mobile
        mobile_template_candidates.each do |v|
          mpath = mobile_path template_path, v
          if partial
            full_path = mobile_template_partial mpath
          else
            full_path = mpath
          end
          if template_exists?(full_path)
            return mpath
          end
        end
      end
      return nil
    end

    if ::ActionPack::VERSION::MAJOR >=2 and ::ActionPack::VERSION::MINOR >= 2
      ### Rails 2.2 or higher
      def template_exists?(template_name)
        send(:_pick_template_without_jpmobile, template_name) ? true : false
      rescue ActionView::MissingTemplate
        false
      end
    else
      ### Rails 2.1 or lower
      def template_exists?(template_name)
        finder.file_exists?(template_name)
      end
    end
  end
end
