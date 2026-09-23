# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hadar::Slot do
  it "indents one unordered list item under its previous sibling without changing other source bytes" do
    original = "# Lists\r\n\r\n- first\r\n- move\r\n- keep\r\n"
    deck = Hadar::Deck.parse(original)
    slot = deck.slide(0).slot(:body)
    editor = slot.rich_text
    change_level(editor, "• move", 1)

    expect(deck.document.source).to eq(original.sub("- move\r\n", "  - move\r\n"))
    expect(list_depths(deck.document.root)).to eq([0, 1, 0])
  end

  it "outdents a deeply nested ordered item one level while preserving its marker and neighboring bytes" do
    original = "# Lists\r\n\r\n- root\r\n  - parent\r\n    1. child\r\n    2. move\r\n- keep\r\n"
    deck = Hadar::Deck.parse(original)
    slot = deck.slide(0).slot(:body)
    editor = slot.rich_text

    expect(editor.paragraph_styles.fetch(line_index(editor, "2. move")).fetch(:level)).to eq(2)
    change_level(editor, "2. move", 1)

    expect(deck.document.source).to eq(original.sub("    2. move\r\n", "  2. move\r\n"))
    expect(list_depths(deck.document.root)).to eq([0, 1, 2, 1, 0])
  end

  it "refuses an outdent that would silently turn the following sibling into a child" do
    original = "# Lists\n\n- root\n  - move\n  - keep\n"
    deck = Hadar::Deck.parse(original)
    editor = deck.slide(0).slot(:body).rich_text

    expect { change_level(editor, "• move", 0) }.to raise_error(Hadar::Error, /neighboring list item/)
    expect(deck.document.source).to eq(original)
  end

  def change_level(editor, line_text, level)
    lines = editor.text.lines
    index = lines.index { |entry| entry.include?(line_text) }
    line = lines[index] if index
    raise "missing rich-text line #{line_text.inspect}" unless line

    offset = lines.take(index).sum(&:bytesize)
    editor.paragraph_style(offset...(offset + line.chomp.bytesize), level: level)
  end

  def line_index(editor, line_text)
    editor.text.lines.index { |line| line.include?(line_text) } || raise("missing rich-text line #{line_text.inspect}")
  end

  def list_depths(node, depth = 0, result = [])
    if %i[list ordered_list].include?(node.type)
      node.children.each do |item|
        result << depth
        item.children.each { |child| list_depths(child, depth + 1, result) }
      end
    else
      node.children.each { |child| list_depths(child, depth, result) }
    end
    result
  end
end
