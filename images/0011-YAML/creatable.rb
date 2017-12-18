#!/usr/bin/env ruby

##
## creatable - �ơ��֥�������ɤ߹���ǲù������ƥ�ץ졼�Ȥǽ��Ϥ���
##

require 'yaml'
require 'erb'


##
## �ᥤ��ץ�������ɽ�����饹
##
## �Ȥ�����
##  main = MainProgram.new()
##  output = main.execute(ARGV)
##  print output if output
##
class MainProgram

  def execute(argv=ARGV)
    # ���ޥ�ɥ��ץ����β���
    options, properties = _parse_options(ARGV)
    return usage() if options[:help]
    raise "�ƥ�ץ졼�Ȥ����ꤵ��Ƥ��ޤ���" unless options[:template]

    # �ǡ����ե�������ɤ߹��ࡣ����ʸ���϶����Ÿ�����롣
    s = ''
    while line = gets()
      s << line.gsub(/([^\t]{8})|([^\t]*)\t/n){[$+].pack("A8")}
    end
    doc = YAML.load(s)

    # �ɤ߹�����ǡ�����ù�����
    manipulator = Manipulator.new(doc)
    manipulator.manipulate()

    # �ƥ�ץ졼�Ȥ򸡺�����
    t = options[:template]
    if test(?f, t)
      template = t
    elsif ENV['CREATABLE_PATH']
      path_list = ENV['CREATABLE_PATH'].split(File::PATH_SEPARATOR)
      template = path_list.find { |path| test(?f, "#{path}/#{t}") }
    end
    raise "'#{t}': �ƥ�ץ졼�Ȥ����Ĥ���ޤ���" unless template
    
    # �ƥ�ץ졼�Ȥ��ɤ߹���ǽ��Ϥ���������
    s = File.read(template)
    trim_mode = '>'        # '%>' �ǽ����ԤǤϲ��Ԥ���Ϥ��ʤ�
    erb = ERB.new(s, $SAFE, trim_mode)
    if options[:multiple]  # ʣ���ե�����ؽ���
      doc['tables'].each do |table|
        context = { 'table' => table, 'properties' => properties }
        output = _eval_erb(erb, context)
        filename = context[:output_filename]   # ���ϥե�����̾
        filename = options[:directory] + "/" + filename if options[:directory]
        File.open(filename, 'w') do |f|
          f.write(output)
          $stderr.puts "generated: #{filename}"
        end if filename
      end
      output = nil
    else                   # ɸ����Ϥؽ���
      context = { 'tables' => doc['tables'], 'properties' => properties }
      output = _eval_erb(erb, context)
    end
    return output
  end

  private

  ## �ƥ�ץ졼�Ȥ�Ŭ�Ѥ��롣
  def _eval_erb(__erb, context)
    # ���Τ褦��ERB#result()������¹Ԥ���᥽�åɤ��Ѱդ���ȡ�
    # ɬ�פ��ѿ��ʤ��ξ��ʤ�context�ˤ�����ƥ�ץ졼�Ȥ��Ϥ���
    # ��ɬ�פʥ��������ѿ����Ϥ��ʤ��Ƥ���褦�ˤʤ롣
    return __erb.result(binding())
  end

  ## �إ�ץ�å�����
  def usage()
     s = ''
     s << "Usage: ruby creatable.rb [-h] [-m] -f template datafile.yaml [...]\n"
     s << "  -h          : �إ��\n"
     s << "  -m          : multiple output file\n"
     s << "  -f template : �ƥ�ץ졼�ȤΥե�����̾\n"
     return s
  end

  ## ���ޥ�ɥ��ץ���󤪤�ӥƥ�ץ졼�ȥץ��ѥƥ�����Ϥ���
  def _parse_options(argv)
    options = {}
    properties = {}
    while argv[0] && argv[0][0] == ?-
      opt = argv.shift
      if opt =~ /^--(.*)/
        # �ƥ�ץ졼�ȥץ��ѥƥ�
        param_str = $1
        if param_str =~ /\A([-\w]+)=(.*)/
          key, value = $1, $2
        else
          key, value = param_str, true
        end
        properties[key] = value
      else
        # ���ޥ�ɥ��ץ����
        case opt
        when '-h'      # �إ��
          options[:help] = true
        when '-f'      # �ƥ�ץ졼��̾
          arg = argv.shift
          raise "-f: �ƥ�ץ졼��̾����ꤷ�Ƥ���������" unless arg
          options[:template] = arg
        when '-m'   # �ơ��֥뤴�Ȥν��ϥե�����
          options[:multiple] = true
        when '-d'   # ������ǥ��쥯�ȥ�
          arg = argv.shift
          raise "-d: �ǥ��쥯�ȥ�̾����ꤷ�Ƥ���������" unless arg
          options[:directory] = arg
        else
          raise "#{opt}: ���ޥ�ɥ��ץ���󤬴ְ�äƤޤ���"
        end
      end
    end
    return options, properties
  end

end


##
## ����ե����뤫���ɤ߹�����ǡ���������å������ù����륯�饹
##
## �Ȥ�����
##   doc = YAML.load(file)
##   manipulator = Manipulator.new()
##   manipulator.manipulate(doc)
##
class Manipulator

  def initialize(doc)
    @defaults = doc['defaults'] || {}
    @tables   = doc['tables']   || []
  end

  ## ����ե����뤫���ɤ߹�����ǡ���������
  def manipulate()
    
    # �֥����̾�����������פ� Hash ���������
    default_columns = {}
    @defaults['columns'].each do |column|
      colname = column['name']
      raise "�����̾������ޤ���" unless colname
      raise "#{colname}: �����̾����ʣ���Ƥ��ޤ���" if default_columns[colname]
      default_columns[colname] = column
    end if @defaults['columns']

    # �ơ��֥�Υ���������å����ͤ����ꤹ��
    tablenames = {}
    @tables.each do |table|
      tblname = table['name']
      raise "�ơ��֥�̾������ޤ���" unless tblname
      raise "#{tblname}: �ơ��֥�̾����ʣ���Ƥ��ޤ���" if tablenames[tblname]
      tablenames[tblname] = true
      colnames = {}
      table['columns'].each do |column|
        colname = column['name']
        raise "#{tblname}: �����̾������ޤ���" unless colname
        raise "#{tblname}.#{colname}: �����̾����ʣ���Ƥ��ޤ���" if colnames[colname]
        colnames[colname] = true
        # �����Υǥե�����ͤ�����
        default_column = default_columns[colname]
        default_column.each do |key, val|
          column[key] = val unless column.key?(key)
        end if default_column
        # ����फ��ơ��֥�ؤΥ�󥯤�����
        column['table'] = table
        # ���������ǻ��Ȥ��Ƥ��륫���Ρ��ǡ������ȥ�������򥳥ԡ�����
        if (ref_column = column['ref']) != nil
          column['type']    = ref_column['type']
          column['width'] ||= ref_column['width']  if ref_column.key?('width')
        end
      end if table['columns']
    end
  end

end


## �ᥤ��ץ�������¹�
main = MainProgram.new
output = main.execute(ARGV)
print output if output