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
end

Plugin.create(:face) do
  defevent :faces, prototype: [Pluggaloid::COLLECT]

  # コンパイル済みのFace
  # @return [Hash{Symbol => Plugin::Face::Face}]
  def faces
    @faces ||= {}
  end

  filter_faces do |f|
    faces.values.each(&f.method(:<<))
    [f]
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

      defface(slug, name: _(name), inherit: :basic_message)
      defface(:"#{slug}_left_header", name: _('%{retriever}のヘッダ（左）') % { retriever: name }, inherit: :left_header)
      defface(:"#{slug}_right_header", name: _('%{retriever}のヘッダ（右）') % { retriever: name }, inherit: :right_header)

      if modelspec[:reply]
        defface(:"#{slug}_mention", name: _('自分宛の%{retriever}') % { retriever: name }, inherit: :mentions)
      end

      if modelspec[:myself]
        defface(:"#{slug}_myself", name: _('自分の%{retriever}') % { retriever: name }, inherit: :myself)
      end
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
          name: 'Default',
          inherit: nil,
          font: 'Sans 10',
          foreground: [0, 0, 0],
          background: [0xffff, 0xffff, 0xffff]

  defface :basic_message,
          name: 'Basic Message',
          inherit: :default

  defface :mention,
          name: 'Mention',
          inherit: :basic_message,
          background: [0xffff, 0xdede, 0xdede]

  defface :myself,
          name: 'Myself Message',
          inherit: :basic_message,
          background: [0xffff, 0xffff, 0xdede]

  defface :quoted_message,
          name: 'Quoted Message',
          inherit: :default,
          font: 'Sans 8'

  defface :quoted_reply_to,
          name: 'Reply To',
          inherit: :quoted_message

  defface :quoted_shared_message,
          name: 'Shared Message',
          inherit: :quoted_message

  defface :header,
          name: 'Header',
          inherit: :default

  defface :left_header,
          name: 'Left Header',
          inherit: :header

  defface :right_header,
          name: 'Right Header',
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
        font _('フォント'), :"face_#{face.slug}_font"
        color _('前景色'), :"face_#{face.slug}_foreground"
        color _('背景色'), :"face_#{face.slug}_background"
      end
    end
  end
end
