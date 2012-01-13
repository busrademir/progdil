#pathname,pythonconfig,yaml kitaplıklarını tanımladı
require 'pathname'
require 'pythonconfig'
require 'yaml'

CONFIG = Config.fetch('presentation', {})

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')
IMAGE_GEOMETRY = [ 733, 550 ]
DEPEND_KEYS    = %w(source css js)
DEPEND_ALWAYS  = %w(media)
#Görevlerin tanımlanması
TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation   = {}
tag            = {}

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end
#Png dosyalarını commentlemek için gerekli fonksiyon
def png_comment(file, string)
  require 'chunky_png'# ilgili kitaplıkları çağırdı
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file) #dosyayı ChunkyPNG ile aç
  image.metadata['Comment'] = 'raked' #metadata daki comment e raked i ata
  image.save(file) # yapılan değişiklikleri dosyaya kaydet
end
#Png optimizasyonu için fonksiyon
def png_optim(file, threshold=40000)
  return if File.new(file).size < threshold #resim boyutu argüman olarak verilen boyuttan küçük ise geri döndür
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked')
end
#Jpg uzantılı resimleri optimize etmeye yarayan fonksiyon
def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}" #resmi optimize etti
  sh "mogrify -comment 'raked' #{file}" #yapılan optimizasyonu commentledi
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"] #png ve jpg dosyalarını sırasıyla pngs ve jpgs
                                                                       #dosyalarına attı,listeledi.

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  (pngs + jpgs).each do |f| #pngs ve jpgs dosyalarını birleştirdi ve f olarak adlandırdı.Sonrasında dosya üzerinde f ismi
                            #ile işlem yapılacak
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i] # resmin boyutu default değerden büyükse tekrar ölçekleyerek küçült
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) } #pngs ve jpgs dosyalarını optimize etti
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f 
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE) #DEFAULT_CONFFILE dosyasının yolunu değişkene attı

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir| #dizinde nokta ile başlamayan dosyalar için
  next unless File.directory?(dir) #dosya dizin değilse
  chdir dir do #dizine girdi
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile #presantation.cfg dosyası varsa 
    config = File.open(conffile, "r") do |f| #bu dosyayı,yoksa default_confile ı confile değişkenine attı
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide'] #config den lanslide bölümünü alıp lanslide isimli değişkene attı
    #lanslide bölümü yoksa hata mesajı verdi ve çıktı
    if ! landslide 
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end
    #lanslide bölümünde destination kullanılmışsa hedef dosya belirtilmemesi için mesaj verdi
    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md') #index.md dosyası varsa dosya adını base değişkenine at
      base = 'index'
      ispublic = true
    elsif File.exists?('presentation.md') #presantation.md dosyası varsa dosya adını base değişkenine at
      base = 'presentation'
      ispublic = false
    else #dosyalardan hiçbiri yoksa hata mesajı ver
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
      exit 1
    end

    basename = base + '.html' #base e html uzantısı ekledi ve basename e attı
    thumbnail = File.to_herepath(base + '.png')
    target = File.to_herepath(basename)

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) } 
    deps.delete(target) #deps.map yaptıktan sonra target ve thumbnail i sildi
    deps.delete(thumbnail)

    tags = [] #boş liste tanımladı

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v| #presantation üzerinde gezerek burdaki bilgileri tanımlanmış olan boş listeye attı
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

presentation.each do |presentation, data| #presantation da gezindi ve dataları isimuzayına attı
  ns = namespace presentation do #isimuzayı tanımlandı
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do
      next unless data[:public]
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end

    task :optim do
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail] # index görevini yerine getirdi

    task :build => [:optim, data[:target], :index] #inşa görevini yerine getirdi

    task :view do
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end

    task :run => [:build, :view] # çalıştırma görevini yerine getirdi

    task :clean do #silme işlemi- target ve thumbnail verilerini sildi
      rm_f data[:target]
      rm_f data[:thumbnail]
    end

    task :default => :build
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do # p isimli isimuzayı oluşturuldu
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do #build görevini yerine getirdi
    index = YAML.load_file(INDEX_FILE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menüsü"
  task :menu do #sunum menüsüde bulunan işlemleri yerine getirdi.
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
