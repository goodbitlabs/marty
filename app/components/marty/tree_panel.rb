# Ext.tree.TreePanel-based component
#
# ATTRIBUTION: this code is based on the netzke-extension module found at:
#       https://github.com/phgrey/netzke-extension
# TODO: Add documentation for usage

class Marty::TreePanel < Netzke::Base
  include ::Netzke::Basepack::DataAccessor
  include ::Netzke::Basepack::Columns

  self.default_instance_config = {
    indicate_leafs:      true,
    auto_scroll:         false,
    root_visible:        false,
    load_inline_data:    false,
    enable_pagination:   false,
    rows_per_page:       30,
    treecolumn:         'tree' # default name for tree column
  }

  def js_configure(c) #:nodoc:
    super
    c.bbar = bbar
  end

  js_configure do |c|
    c.extend = "Ext.tree.TreePanel"
    c.mixin
    c.root_visible = false
  end

  # Configure dynamic JS properties for instantiation
  def js_config
    super.tap do |c|
      # Hand over inline data to the js config hash
      c[:inline_data] = get_data if config[:load_inline_data]
    end
  end

  def configure(c) #:nodoc:
    super
    c.title ||= self.class.js_config.properties[:title] ||
      data_class.name.pluralize
    c.columns = final_columns(with_meta: true)

    # Set it to the primary key if not given and camelize it Setting
    # it to anything else than the primary key is especially useful
    # when instances of different class are shown in one tree because
    # the primary key MUST be unique!
    c.pri = (c.pri || data_class.primary_key).to_s.camelize(:lower)

    # Add extra fields for a tree: A method ':name(r)' is called for
    # every record to retrieve the value
    c.extra_fields ||= []

    # This will call leaf?(r) for every record
    c.extra_fields << {name: 'leaf', type: 'boolean'}

    # This will call expanded?(r) for every record
    c.extra_fields << {name: 'expanded', type: 'boolean'}

    # only if the node id property is different from the data class'
    # primary key, we need to add and extra field
    c.extra_fields << {name: c.pri.to_s.camelize(:lower), type: 'string'} if
      c.pri != data_class.primary_key
  end

  def config
    @config ||= ActiveSupport::OrderedOptions.new.tap do |c|
      # extend with data_store convenient config object
      c.data_store = ActiveSupport::OrderedOptions.new
    end
  end

  def bbar
    config[:bbar]
  end

  # Sets the xtype to 'treecolumn' for the column with name equal to
  # the :treecolumn value of the config
  def set_default_xtype(c)
    c[:xtype] = 'treecolumn' if c[:name].to_s == config[:treecolumn].to_s
  end

  # Set data_index -- The name of the field configuration of the Ext
  # JS model will be set to this value This is neccessary since the
  # data is serialized as a hash (with camelized keys) so the
  # data_index must also be camelized
  def set_default_data_index(c)
    c[:data_index] = c[:name].camelize(:lower)
  end

  # Call super and then set the data_index
  def augment_column_config(c)
    super
    set_default_data_index(c)
    set_default_xtype c
  end

  # @!method get_data_endpoint
  #
  # Returns something like:
  # [
  # { 'id'=> 1, 'text'=> 'A folder Node', 'leaf'=> false },
  # { 'id'=> 2, 'text'=> 'A leaf Node', 'leaf'=> true }
  # ]
  #
  # @param [Hash] params
  endpoint :get_data do |params, this|
    this.merge! get_data(params)
  end

  # Method that is called by the get_data endpoint
  # Calls the get_children method and returns the serialized records
  #
  # @param [] *args takes any arguments
  # @return [Hash] all the serialized data
  def get_data(*args)
    params = args.first || {} # params are optional!

    sortp = params["sort"]

    # Giant hack to fix property field used in sort.  Not sure why
    # this is coming in camelized.
    if sortp.is_a?(Array)
      sortp.each { |h|
        h["property"] = h["property"].underscore if
        h.is_a?(Hash) && h["property"]
      }
    end

    if !config[:prohibit_read]
      {}.tap do |res|
        # set children to an instance variable in order to access them later
        @records = get_children(params)

        # Serialize children
        res[:data] = serialize_data(@records)

        res[:total] = count_records(params) if
          config[:enable_pagination] &&
          (params[:node].nil? || params[:node] == 'root')
      end
    else
      flash :error => "You don't have permissions to read data"
      { :netzke_feedback => @flash }
    end
  end

  # Serializes an array of objects
  #
  # @param [Array] records
  # @return [Array] the serialized data
  def serialize_data(records)
    records.map { |r|
      data_adapter.record_to_hash(r, final_columns(:with_meta => true)).tap { |h|

        config[:extra_fields].each do |f|
          name = f[:name].underscore.to_sym
          h[name] = send("#{name}#{f[:type] == 'boolean' ? '?' : ''}", r)
        end

        inline_children = get_inline_children(r)
        h[:data] = serialize_data(inline_children) unless inline_children.nil?
        h
      }
    }
  end

  # Retrieves all children for a node
  # Note: It's recommended to override this method
  #
  # @param [Hash] params
  # @return [Array] array of records
  def get_children(params)
    scope_data_class(params) do
      params[:limit] = config[:rows_per_page] if
        config[:enable_pagination] && (params[:node].nil? || params[:node] == 'root')
      params[:scope] = config[:scope]
      data_adapter.get_records(params, final_columns)
    end
  end

  # Scopes the data class depending on the config of the parent_key and the node
  #
  # @param [Hash] params
  def scope_data_class(params, &block)
    if config[:parent_key]
      # The value of the pri property of the expanded node is passed
      # as params[:node] ('root' for the root collection)
      if params[:node].nil? || params[:node] == 'root'
        data_class.where(config[:parent_key] => nil).scoping do
          yield
        end
      else
        data_class.where(config[:parent_key] => params[:node]).scoping do
          yield
        end
      end
    else
      yield
    end
  end

  # Counts the total records
  #
  # @param [Hash] params
  # @return [Fixnum] The number of records
  def count_records(params)
    scope_data_class(params) do
      params[:scope] = config[:scope]
      data_adapter.count_records(params, final_columns)
    end
  end

  # Should return all children of the record that should also be
  # serialized in the current request
  # Note: It's recommended to override this method
  #
  # @param [Object] r The record for which the inline children should be loaded
  # @return [NilClass, Array] If nil is returned, the tree doesn't
  # know anything about any children, so opening the node will cause
  # another request.  If an empty array is returned, the tree assumes
  # that there are no children available for this node (and thus you
  # can't open it!)
  def get_inline_children(r)
    nil
  end

  # Is the record a leaf or not?
  # Note: It's recommended to override this method
  #
  # @param [Object] r
  # @return [Boolean] Whether the node is a leaf or not
  def leaf?(r)
    r.children.empty?
  end

  # Is the record a expanded or not?
  # Note: It's recommended to override this method
  #
  # @param [Object] r
  # @return [Boolean] Whether the node is expanded or not
  def expanded?(r)
    false
  end

  # Is the record a leaf or not?
  # Note: It's recommended to override this method
  #
  # @param [Object] r
  # @return [Boolean] Whether the node is a leaf or not
  def node_id(r)
    r.send(data_class.primary_key)
  end
end
