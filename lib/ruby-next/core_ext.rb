# frozen_string_literal: true

require_relative "core"

# Monkey-patch core classes using the same patches as for refinements
RubyNext::Core.patches.extensions.each do |mod, patches|
  patches.each do |patch|
    if patch.prepend?
      mod.prepend(patch.to_module)
    else
      mod.module_eval(&patch)
    end
  end
end

RubyNext::Core.strategy = :core_ext
