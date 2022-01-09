# frozen_string_literal: true

module Plugin::Face
  ATTRIBUTES = %i[font foreground background]

  class Face
    def to_s
      "Face(:#{slug})"
    end

    def inspect
      "#<Plugin::Face::Face #{slug.inspect}>"
    end

    ATTRIBUTES.each do |attr|
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{attr}; end

        def #{attr}_responder
          nil
        end
      RUBY
    end
  end

  module DivaModelExtension
    refine Diva::Model do
      def suitable_face
        if from_me?
          :myself
        elsif to_me?
          :mention
        else
          :basic_message
        end
      end
    end
  end
end

using Plugin::Face::DivaModelExtension

Plugin.create(:face) do
  defevent :faces, prototype: [Pluggaloid::COLLECT]

  # コンパイル済みのFace
  # @return [Hash{Symbol => Plugin::Face::Face}]
  def faces
    @faces ||= {}
  end

  # Diva modelから生成されたFace
  # Model slug => Face slug => Face
  # @return [Hash{Symbol => Hash{ Symbol => Plugin::Face::Face }}]
  def model_faces
    @model_faces ||= {}
  end

  # Diva modelから生成され、指定されたFaceを継承した固有のFaceを得る
  # もし固有のFaceが定義されていない場合、一般的なFaceを代替として用いる
  # @param [Diva::Model] model
  # @param [Symbol] face
  # @return [Plugin::Face::Face]
  def concrete_face_by_model(model, face:)
    model_faces.dig(model.class.slug, face) || faces[face]
  end

  filter_faces do |f|
    faces.values.each(&f.method(:<<))
    [f]
  end

  # TODO: 選択中もFaceにしちゃっていいかもしれんがどうだろう
  # filter_message_selected_bg_color do |model, color|
  #   color and return [model, color]
  #   slug = model.class.slug
  #   color = UserConfig[:"#{slug}_selected_bg"] || UserConfig[:mumble_selected_bg]
  #   [model, color]
  # end

  filter_subparts_replyviewer_background_color do |message, color|
    [message, color || faces[:quoted_reply_to].background]
  end

  filter_subparts_quote_background_color do |message, color|
    [message, color || faces[:quoted_message].background]
  end

  filter_message_font do |message, font|
    [message, font || concrete_face_by_model(message, face: message.suitable_face).font]
  end

  filter_message_font_color do |message, color|
    [message, color || concrete_face_by_model(message, face: message.suitable_face).foreground]
  end

  filter_message_bg_color do |message, color|
    [message, color || concrete_face_by_model(message, face: message.suitable_face).background]
  end

  filter_message_header_left_font do |message, font|
    [message, font || concrete_face_by_model(message, face: :left_header).font]
  end

  filter_message_header_left_font_color do |message, color|
    [message, color || concrete_face_by_model(message, face: :left_header).foreground]
  end

  filter_message_header_right_font do |message, font|
    [message, font || concrete_face_by_model(message, face: :right_header).font]
  end

  filter_message_header_right_font_color do |message, color|
    [message, color || concrete_face_by_model(message, face: :right_header).foreground]
  end

  # 新しいFaceを定義する
  # 指定可能な属性は {Plugin::Face::ATTRIBUTES} に列挙されているもの
  # @param [Symbol] slug Faceの識別子
  # @param [String] name 表示用の名前
  # @param [Symbol, nil] inherit 属性を継承するFace
  defdsl :defface do |slug, name: face.to_s, inherit: :default, **attrs|
    if inherit && !faces[inherit]
      error "Undefined inheritance parent #{inherit}"
    end
    faces[slug] = compile(slug, name: name, inherit: inherit, **attrs)
  end

  # Timelineに表示可能なModelからFace定義を自動生成する
  def define_from_model
    Plugin.filtering(:retrievers, []).first.select(&:timeline).each do |modelspec|
      slug = modelspec[:slug]
      name = modelspec[:name]

      faces = {}
      faces[:basic_message] = defface(slug, name: _(name), inherit: :basic_message)
      faces[:left_header] = defface(:"#{slug}_left_header", name: _('%{retriever}のヘッダ（左）') % { retriever: name }, inherit: :left_header)
      faces[:right_header] = defface(:"#{slug}_right_header", name: _('%{retriever}のヘッダ（右）') % { retriever: name }, inherit: :right_header)

      if modelspec[:reply]
        faces[:mention] = defface(:"#{slug}_mention", name: _('自分宛の%{retriever}') % { retriever: name }, inherit: :mention)
      end

      if modelspec[:myself]
        faces[:myself] = defface(:"#{slug}_myself", name: _('自分の%{retriever}') % { retriever: name }, inherit: :myself)
      end

      model_faces[slug] = faces
    end
  end

  # Face定義から、そのFaceの設定値を得るためのオブジェクトを生成する
  def compile(slug, name:, inherit:, **attrs)
    klass = Class.new(faces[inherit]&.class || Plugin::Face::Face) do
      define_method(:slug) { slug }
      define_singleton_method(:slug) { slug }
      define_method(:name) { name }
      define_singleton_method(:name) { name }

      Plugin::Face::ATTRIBUTES.each do |attr|
        config_key = :"face_#{slug}_#{attr}"
        default_value = attrs[attr]

        define_method(attr) do
          UserConfig[config_key] || default_value || super()
        end

        define_method(:"#{attr}_responder") do
          case
          when UserConfig[config_key]
            [slug, :user]
          when default_value
            [slug, :default]
          else
            super()
          end
        end
      end
    end

    klass.new
  end

  defface :default,
          name: _('標準'),
          inherit: nil,
          font: 'Sans 10',
          foreground: [0, 0, 0],
          background: [0xffff, 0xffff, 0xffff]

  defface :basic_message,
          name: _('すべての投稿'),
          inherit: :default

  defface :mention,
          name: _('自分宛の投稿'),
          inherit: :basic_message,
          background: [0xffff, 0xdede, 0xdede]

  defface :myself,
          name: _('自分の投稿'),
          inherit: :basic_message,
          background: [0xffff, 0xffff, 0xdede]

  defface :quoted_message,
          name: _('引用'),
          inherit: :default,
          font: 'Sans 8'

  defface :quoted_reply_to,
          name: _('リプライ先'),
          inherit: :quoted_message

  defface :quoted_shared_message,
          name: _('コメント付きシェア'),
          inherit: :quoted_message

  defface :header,
          name: _('ヘッダ'),
          inherit: :default

  defface :left_header,
          name: _('ヘッダ（左）'),
          inherit: :header

  defface :right_header,
          name: _('ヘッダ（右）'),
          inherit: :header,
          foreground: [0x9999, 0x9999, 0x9999]

  Delayer.new { define_from_model }

  def dump
    # TODO: write to file
    io = StringIO.new
    io.puts 'digraph {'
    io.puts '  rankdir="RL"'
    faces.each do |slug, spec|
      if spec.class.superclass == Plugin::Face::Face
        io.puts "  #{slug};"
      else
        io.puts "  #{slug} -> #{spec.class.superclass.slug};"
      end
    end
    io.puts '}'

    puts io.string
  end
end

Plugin.create(:face_gtk) do
  settings 'Faces' do
    Plugin.collect(:faces).each do |face|
      settings(_(face.name)) do
        if face.class.superclass != Plugin::Face::Face
          markup _("未設定の項目には <b><u>%{inherit}</u></b> の設定が使用されます") % { inherit: face.class.superclass.name }
        end
        font _('フォント'), :"face_#{face.slug}_font"
        color _('前景色'), :"face_#{face.slug}_foreground"
        color _('背景色'), :"face_#{face.slug}_background"
      end
    end
  end
end
