require 'mcfly'

class Marty::Script < Marty::Base
  has_mcfly

  validates_presence_of :name, :body
  mcfly_validates_uniqueness_of :name
  validates_format_of :name, {
    with: /\A[A-Z][a-zA-Z0-9]*\z/,
    message: I18n.t('script.save_error'),
  }

  belongs_to :user, class_name: "Marty::User"

  gen_mcfly_lookup :lookup, {
    name: false,
  }

  gen_mcfly_lookup :get_all, {}, mode: :all

  # find script by name/tag
  def self.find_script(sname, tag=nil)
    tag = Marty::Tag.map_to_tag(tag)
    Marty::Script.lookup(tag.created_dt, sname)
  end

  def find_tag
    # find the first tag created after this script.
    Marty::Tag.where("created_dt >= ?", created_dt).order(:created_dt).first
  end

  def self.create_script(name, body)
    script      = new
    script.name = name
    script.body = body
    script.save
    script
  end

  def self.load_a_script(sname, body, dt=nil)
    s = Marty::Script.lookup('infinity', sname)

    if !s
      s = Marty::Script.new
      s.body = body
      s.name = sname
      s.created_dt = dt if dt
      s.save!
    elsif s.body != body
      s.body = body
      s.created_dt = dt if dt
      s.save!
    end
  end

  def self.load_script_bodies(bodies, dt=nil)
    bodies.each {
      |sname, body|
      load_a_script(sname, body, dt)
    }

    # Create a new tag if scripts were modified after the last tag
    tag = Marty::Tag.get_latest1
    latest = Marty::Script.order("created_dt DESC").first

    tag_time = (dt || [latest.created_dt, Time.now].max) + 1.second

    # If no tag_time is provided, the tag created_dt will be the same
    # as the scripts.
    tag = Marty::Tag.do_create(tag_time, "tagged from load scripts") if
      !tag or tag.created_dt <= latest.created_dt

    tag
  end

  def self.load_scripts(path=nil, dt=nil)
    path ||= "#{Rails.root}/db/gemini"

    # read delorean files from the directory
    bodies = Dir.glob("#{path}/*\.dl").each_with_object({}) {
      |fpath, h|
      fname = File.basename(fpath)[0..-4].camelize
      h[fname] = File.read(fpath)
    }

    load_script_bodies(bodies, dt)
  end

  def self.delete_scripts
    ActiveRecord::Base.connection.
      execute("ALTER TABLE marty_scripts DISABLE TRIGGER ALL;")
    Marty::Script.delete_all
    ActiveRecord::Base.connection.
      execute("ALTER TABLE marty_scripts ENABLE TRIGGER ALL;")
  end

  delorean_fn :eval_to_hash, sig: 5 do
    |dt, script, node, attrs, params|
    tag = Marty::Tag.find_match(dt)

    # IMPORTANT: engine evals (e.g. eval_to_hash) modify the
    # params. So, need to clone it.
    params = params.clone

    raise "no tag found for #{dt}" unless tag

    engine = Marty::ScriptSet.new(tag).get_engine(script)
    res = engine.eval_to_hash(node, attrs, params)

    # FIXME: should sanitize res to make sure that no nodes are being
    # passed back.  It's likely that nodes which are not from the
    # current tag can caused problems.
    res
  end
end
