require 'pathname'

module AssetImporter
  # tries to import all files found under +path+ as Paperclipped Asset
  # assumes that +path+ is under public/assets
  def self.import(path)
    import_folder(Pathname.new(path))
  end

  def self.assets_dir_for(pathname)
   return nil if pathname.root? || !pathname.exist?
    
    if pathname.directory? && pathname.basename.to_s == 'assets'
      return pathname
    end
    
   assets_dir_for(pathname.parent)
  end

  def self.import_folder(pathname)
    asset_mapping = {}
    assets_dir = assets_dir_for(pathname)
    if !assets_dir
      puts "Directory to import must be under the assets directory"
      return
    end

    pathname.children.collect do |image|
      filename = image.relative_path_from(assets_dir.parent)
      next if filename.to_s =~ /^\./
      if image.directory?
        puts "Importing directory '#{image}'"
        self.import_folder(image)
      else
        begin
          asset = Asset.create! :asset => image.open
          asset_mapping[filename.to_s.sub(/^\//, '')] = asset
        rescue StandardError => e
          puts "Could not create Asset for file #{filename}"
          puts "Reason was: #{e.message}"
        end
      end
    end
    puts "Rewriting URLs in content"
    rewrite_urls(asset_mapping)
  end
  
  def self.rewrite_urls(asset_mapping)
    @asset_mapping = asset_mapping
    [PagePart, Snippet, Layout].each do |klass|
      klass.find_each do |resource|
        fix resource
        resource.content_will_change! # ActiveRecord::Dirty fails to notice the content change.
        resource.save!
      end
    end
  end

  def self.fix(resource)
    resource.content.gsub!(%r{/?(?:\.\./)*(assets/[^'"\n)]+[^'")\s])}) do |asset_path|
      dir, file = File.split($1)
      old_asset = File.join(dir, URI.decode(file))
      asset = @asset_mapping[old_asset]
      if asset
        puts "#{old_asset} => #{asset.url}"
        asset.url
      else
        asset_path
      end
    end
  end
  
end
