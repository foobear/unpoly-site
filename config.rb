lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

$LOAD_PATH.unshift('lib')
$LOAD_PATH.unshift('vendor/unpoly-local/lib')

require 'ext/rack/support_colons_in_path'
require 'unpoly/rails/version'
require 'unpoly/tasks'
require 'unpoly/guide'
require 'unpoly/example'
require 'fileutils'
require 'kramdown'
require 'kramdown-parser-gfm'

##
# Extensions
#
activate :sprockets

# Produce */index.html files
activate :directory_indexes


##
# Build-specific configuration
#
configure :build do
  # Minify CSS on build
  activate :minify_css

  # Minify Javascript on build
  activate :minify_javascript, compressor: proc {
    require 'uglifier'
    Uglifier.new(harmony: true)
  }

  # Enable cache buster
  activate :asset_hash

  # after_build do
  #   puts 'Copying .htaccess file ...'
  #   from = 'source/.htaccess'
  #   to = 'build/.htaccess'
  #   FileUtils.copy(from, to)
  # end

end



##
# Layout
#
page '/*.xml', layout: false
page '/*.json', layout: false
page '/*.txt', layout: false
page '/*.html', layout: 'guide'

sprockets.append_path File.expand_path('vendor/asset-libs')
sprockets.append_path File.expand_path('vendor/unpoly-local/lib/assets/javascripts')
sprockets.append_path File.expand_path('vendor/unpoly-local/lib/assets/stylesheets')


Unpoly::Guide.current.reload

##
# Proxy pages (http://middlemanapp.com/basics/dynamic-pages/)
#
Unpoly::Guide.current.interfaces.each do |interface|
  path = "#{interface.guide_path}.html" # the .html will be removed by Middleman's pretty directory indexes
  puts "Proxy: #{path}"
  proxy path, "/api/interface_template.html", locals: { interface_name: interface.name }, ignore: true
end

Unpoly::Guide.current.all_feature_guide_ids.each do |guide_id|
  path = "/#{guide_id}.html" # the .html will be removed by Middleman's pretty directory indexes
  puts "Proxy: #{path}"
  proxy path, "/api/feature_template.html", locals: { guide_id: guide_id }, ignore: true
end

Unpoly::Guide.current.versions.each do |version|
  path = "/changes/#{version}.html" # the .html will be removed by Middleman's pretty directory indexes
  puts "Proxy: #{path}"
  proxy path, "/changes/release_template.html", locals: { version: version }, ignore: true
end

Unpoly::Example.all.each do |example|

  proxy example.index_path, "examples/index.html", locals: { example: example }, layout: false, ignore: true, directory_index: false

  example.stylesheets.each do |asset|
    puts "Example stylesheet: #{asset.path}"
    proxy asset.path, "/examples/stylesheet", locals: { asset: asset }, layout: false, ignore: true, directory_index: false
  end

  example.javascripts.each do |asset|
    puts "Example javascripts: #{asset.path}"
    proxy asset.path, "/examples/javascript", locals: { asset: asset }, layout: false, ignore: true, directory_index: false
  end

  example.pages.each do |asset|
    puts "Example pages: #{asset.path}"
    proxy asset.path, "/examples/page.html", locals: { asset: asset }, layout: false, ignore: true, directory_index: false
  end

end


###
# Helpers
#
helpers do

  def guide
    @guide ||= Unpoly::Guide.current
  end

  def gem_version
    Unpoly::Tasks.gem_version
  end

  def pre_release?
    Unpoly::Tasks.pre_release?
  end

  def markdown(text, **options)
    # text = text.gsub(/<`(.*?)`>/) do |match|
    #   code = $1
    #   slug = Unpoly::Guide::Util.slugify(code)
    #   "[`#{code}`](/#{slug})"
    # end

    doc = Kramdown::Document.new(text,
                                 input: 'GFM',
                                 remove_span_html_tags: true,
                                 enable_coderay: false,
                                 smart_quotes: ["apos", "apos", "quot", "quot"],
                                 hard_wrap: false
    )
    # Blindly remove any HTML tag from the document, including "span" elements
    # (see option above). This will NOT remove HTML tags from code examples.
    doc.to_remove_html_tags
    html = doc.to_html
    html = postprocess_markdown(html, **options)
    html
  end

  def postprocess_markdown(html, autolink_code: true, strip_links: false, pictures: true)
    if autolink_code || strip_links || pictures
      nokogiri_doc = Nokogiri::HTML.fragment(html)
    end

    if strip_links
      nokogiri_doc.css('a').each do |link|
        link.replace(link.children)
      end
    elsif autolink_code
      autolink_code_in_nokogiri_doc(nokogiri_doc)
    end

    if pictures
      nokogiri_doc.css('img:not([class])').each do |img|
        img[:class] = 'picture has_border'
      end
    end

    nokogiri_doc.to_html
  end

  def autolink_code_in_nokogiri_doc(nokogiri_doc)
    codes = nokogiri_doc.css('code')

    current_path = current_page.path
    current_path = current_path.sub(/\/index\.html$/, '')
    current_path = current_path.sub(/\/$/, '')
    current_path = current_path.sub(/\.html$/, '')
    current_path = "/#{current_path}" unless current_path[0] == '/'

    codes.each do |code_element|
      text = code_element.text
      unless text.include?("\n") || text =~ /^["']/
        if code_element.ancestors('a, pre').blank?
          guide_id = text
          guide_id = guide_id.sub('#', '.prototype.')
          hash = nil

          if guide_id =~ /^(up\..+?\.config)\.(.+?)$/
            guide_id = $1
            hash = "config.#{$2}"
          end

          guide_id = Unpoly::Guide::Util.slugify(guide_id)
          if guide.guide_id_exists?(guide_id)
            path = "/#{guide_id}"
            unless path == current_path
              href = [path, hash].compact.join('#')
              code_element.wrap("<a href='#{h href}'></a>")
            end
          end
        end
      end
    end
  end

  def hyperlink_to_reference(reference)
    label = reference.title
    if reference.code?
      label = content_tag(:code, label)
    end
    link_to label, reference.guide_path, class: 'hyperlink'
  end

  def markdown_prose(text, **options)
    "<div class='prose'>#{markdown(text, **options)}</div>"
  end

  def window_title
    page_title = @page_title || current_page.data.title

    if page_title.present?
      "#{page_title} - Unpoly"
    else
      "Unpoly: Unobtrusive JavaScript framework"
    end
  end

  def unpoly_library_size(files = nil)
    files ||= [
      'unpoly.min.js',
      'unpoly.min.css'
    ]
    files = Array.wrap(files)
    paths = files.map { |file| local_library_file_path(file) }

    unless paths.all? { |path| File.file?(path) }
      return '?? KB'
    end

    require 'active_support/gzip'
    source = ''
    paths.each do |path|
      File.exists?(path) or raise "Asset not found: #{path}"
      source << File.read(path)
    end
    kbs = (ActiveSupport::Gzip.compress(source).length / 1024.0).round(1)
    "#{kbs} KB"
  end

  def local_library_file_path(file)
    "#{Unpoly::Guide.current.path}/dist/#{file}"
  end

  def hyperlink(label, href, options = {})
    options[:class] = "hyperlink #{options[:class]}"
    link_to label, href, options
  end

  def modal_hyperlink(label, href, options = {})
    options[:class] = "hyperlink #{options[:class]}"
    options['up-layer'] = 'new modal'
    link_to label, href, options
  end

  def node_link(label, href, options = {})
    options[:class] = "node__self #{options[:class]}"
    # options['up-layer'] = 'page' # don't open drawer links within the drawer (both drawer and page contain .content)
    link_to label, href, options
  end

  def breadcrumb_link(label, href)
    link_to label, href, class: 'breadcrumb', 'up-restore-scroll': true
  end

  def cdn_url(file)
    "https://unpkg.com/unpoly@#{guide.version}/#{file}"
  end

  def cdn_js_include(file)
    %Q(<script src="#{cdn_url(file)}"></script>)
  end

  def cdn_css_include(file)
    %Q(<link rel="stylesheet" href="#{cdn_url(file)}">)
  end

  # def sri_attrs(file)
  #   %{integrity="#{sri_hash(file)}" crossorigin="anonymous"}
  # end
  #
  # def sri_hash(file)
  #   path = local_library_file_path(file)
  #   hash_base64 = `openssl dgst -sha384 -binary #{path} | openssl base64 -A`.presence or raise "Error calling openssl"
  #   hash_base64 = hash_base64.strip
  #   "sha384-#{hash_base64}"
  # end

  BUILTIN_TYPE_URLS = {
    # 'string' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String',
    'undefined' => 'https://developer.mozilla.org/en-US/docs/Glossary/undefined',
    # 'Array' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array',
    'null' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/null',
    # 'number' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number',
    # 'boolean' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Boolean',
    'Object' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Working_with_Objects',
    'Promise' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Using_promises',
    'FormData' => 'https://developer.mozilla.org/en-US/docs/Web/API/FormData',
    'Event' => 'https://developer.mozilla.org/en-US/docs/Web/API/Event',
    'Error' => 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error',
    'XMLHttpRequest' => 'https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest',
    'NodeList' => 'https://developer.mozilla.org/en-US/docs/Web/API/NodeList',
    'Element' => 'https://developer.mozilla.org/de/docs/Web/API/Element',
    'jQuery' => 'https://learn.jquery.com/using-jquery-core/jquery-object/',
  }

  def type(type_or_types)
    types = Array.wrap(type_or_types)
    parts = types.map { |type|
      type = h(type)
      type.gsub(/[a-z\.]+/i) { |subtype|

        begin
          url = guide.interface_for_name!(subtype).guide_path
        rescue Unpoly::Guide::UnknownInterface
          url = BUILTIN_TYPE_URLS[subtype]
        end

        if url
          "<a href='#{h url}'>#{subtype}</a>"
        else
          subtype
        end
      }
    }

    or_tag = "<span class='type__or'>or</span>"

    "<span class='type'>#{parts.join(or_tag)}</span>"
  end

  def edit_button(documentable)
    commit = config[:environment] == 'development' ? guide.git_revision : guide.git_version_tag
    url = documentable.text_source.github_url(guide, commit: commit)
    link_to '<i class="fa fa-edit"></i> Edit <span class="edit_link__etc">this page</span>', url, target: '_blank', class: 'hyperlink edit_link'
  end

  def revision_on_github_button(revision)
    url = revision.github_browse_url
    link_to '<i class="fa fa-code"></i> Revision code', url, target: '_blank', class: 'hyperlink edit_link'
  end

  def feature_preview(feature)
    partial('api/feature_preview', locals: { feature: feature })
  end

  def url_link(url, options = {})
    link_to url, url, options
  end

  def menu(search: false, &block)
    nodes = capture_html(&block)
    @menu_html = partial('menu/menu', locals: { nodes: nodes, search: search })
  end

  def page_title(title)
    @page_title = title
    return title
  end

  def slugify(text)
    Unpoly::Guide::Util.slugify(text)
  end

end
