# frozen_string_literal: true
require 'nokogiri'
require 'draftjs_exporter/entity_state'
require 'draftjs_exporter/style_state'
require 'draftjs_exporter/command'

module DraftjsExporter
  class HTML
    attr_reader :block_map, :style_map, :entity_decorators

    def initialize(block_map:, style_map:, entity_decorators:)
      @block_map = block_map
      @style_map = style_map
      @entity_decorators = entity_decorators
    end

    def call(content_state)
      content_state.fetch(:blocks, []).map { |block|
        content_state_block(block, content_state.fetch(:entityMap, {}))
      }.inject(:+)
    end

    private

    def content_state_block(block, entity_map)
      document = Nokogiri::HTML::Document.new
      fragment = Nokogiri::HTML::DocumentFragment.new(document)
      type = block.fetch(:type, 'unstyled')
      element = document.create_element(*block_options(type)) { |e|
        block_contents(e, block, entity_map)
      }
      fragment.add_child(element).to_s
    end

    def block_contents(element, block, entity_map)
      style_state = StyleState.new(style_map)
      entity_state = EntityState.new(element, entity_decorators, entity_map)
      build_command_groups(block).each do |text, commands|
        commands.each do |command|
          entity_state.apply(command)
          style_state.apply(command)
        end

        add_node(entity_state.current_parent, text, style_state)
      end
    end

    def block_options(type)
      options = block_map.fetch(type)
      return [options.fetch(:element)] unless options.key?(:wrapper)

      wrapper = options.fetch(:wrapper)
      name = wrapper[0]
      config = wrapper[1] || {}
      options = {}
      options[:class] = config.fetch(:className) if config.key?(:className)
      [name, options]
    end

    def add_node(element, text, state)
      document = element.document
      node = if state.text?
               document.create_text_node(text)
             else
               document.create_element('span', text, state.element_attributes)
             end
      element.add_child(node)
    end

    def build_command_groups(block)
      text = block.fetch(:text)
      grouped = build_commands(block).group_by(&:index).sort
      grouped.map.with_index { |(index, commands), command_index|
        start_index = index
        next_group = grouped[command_index + 1]
        stop_index = (next_group && next_group.first || 0) - 1
        [text.slice(start_index..stop_index), commands]
      }
    end

    def build_commands(block)
      [
        Command.new(:start_text, 0),
        Command.new(:stop_text, block.fetch(:text).size)
      ] +
        build_range_commands(:inline_style, :style, block.fetch(:inlineStyleRanges)) +
        build_range_commands(:entity, :key, block.fetch(:entityRanges))
    end

    def build_range_commands(name, data_key, ranges)
      ranges.flat_map { |range|
        data = range.fetch(data_key)
        start = range.fetch(:offset)
        stop = start + range.fetch(:length)
        [
          Command.new("start_#{name}".to_sym, start, data),
          Command.new("stop_#{name}".to_sym, stop, data)
        ]
      }
    end
  end
end
