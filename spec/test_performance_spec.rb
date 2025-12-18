require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    let(:generator) { described_class.new }
    let(:user_ids) { [1, 2] }
    let(:posts1) { double('Posts1', count: 2) }
    let(:posts2) { double('Posts2', count: 3) }
    let(:user1) { double('User1', id: 1, name: 'Alice', posts: posts1) }
    let(:user2) { double('User2', id: 2, name: 'Bob', posts: posts2) }

    before do
      stub_const('User', Class.new)
    end

    it 'queries each id, loads posts, and prints a line per user' do
      expect(User).to receive(:find).with(1).and_return(user1)
      expect(User).to receive(:find).with(2).and_return(user2)
      expect do
        generator.generate_user_report(user_ids)
      end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
    end

    it 'prints nothing when user_ids is empty and does not query the database' do
      expect(User).not_to receive(:find)
      expect do
        generator.generate_user_report([])
      end.to output('').to_stdout
    end

    it 'raises an error when user_ids is nil' do
      expect do
        generator.generate_user_report(nil)
      end.to raise_error(NoMethodError)
    end

    it 'raises if a user has nil posts' do
      user_with_nil_posts = double('User', id: 3, name: 'Eve', posts: nil)
      expect(User).to receive(:find).with(3).and_return(user_with_nil_posts)
      expect do
        generator.generate_user_report([3])
      end.to raise_error(NoMethodError)
    end
  end

  describe '#build_csv' do
    let(:generator) { described_class.new }
    let(:record_class) { Struct.new(:id, :name) }

    it 'builds a CSV string by concatenation' do
      records = [record_class.new(1, 'Alpha'), record_class.new(2, 'Beta')]
      result = generator.build_csv(records)
      expect(result).to eq("1,Alpha\n2,Beta\n")
    end

    it 'returns empty string for empty records' do
      result = generator.build_csv([])
      expect(result).to eq('')
    end

    it 'raises when records is nil' do
      expect do
        generator.build_csv(nil)
      end.to raise_error(NoMethodError)
    end

    it 'handles numeric and string conversions' do
      mixed = [double('R1', id: 10, name: 'X'), double('R2', id: '20', name: 30)]
      result = generator.build_csv(mixed)
      expect(result).to eq("10,X\n20,30\n")
    end
  end

  describe '#find_matches' do
    let(:generator) { described_class.new }

    it 'returns duplicates for multiple matches as implemented' do
      list_a = [1, 2, 3]
      list_b = [2, 3, 4, 2]
      result = generator.find_matches(list_a, list_b)
      expect(result).to eq([2, 2, 3])
    end

    it 'returns empty array when no matches' do
      result = generator.find_matches([1, 5], [2, 3, 4])
      expect(result).to eq([])
    end

    it 'supports repeated items in both lists' do
      list_a = [1, 1, 2]
      list_b = [1, 2, 2]
      result = generator.find_matches(list_a, list_b)
      expect(result).to eq([1, 1, 2, 2])
    end

    it 'handles empty lists' do
      expect(generator.find_matches([], [])).to eq([])
    end

    it 'raises when either list is nil' do
      expect do
        generator.find_matches(nil, [])
      end.to raise_error(NoMethodError)
      expect do
        generator.find_matches([], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    let(:generator) { described_class.new }
    let(:user1) { double('User1') }
    let(:user2) { double('User2') }

    before do
      stub_const('User', Class.new)
    end

    it 'calls send_email for each user returned by User.all' do
      allow(User).to receive(:all).and_return([user1, user2])
      expect(generator).to receive(:send_email).with(user1).ordered
      expect(generator).to receive(:send_email).with(user2).ordered
      generator.process_all_users
    end

    it 'does nothing when there are no users' do
      allow(User).to receive(:all).and_return([])
      expect(generator).not_to receive(:send_email)
      generator.process_all_users
    end

    it 'bubbles up errors from send_email' do
      allow(User).to receive(:all).and_return([user1, user2])
      allow(generator).to receive(:send_email).with(user1).and_raise(StandardError, 'boom')
      expect do
        generator.process_all_users
      end.to raise_error(StandardError, 'boom')
    end

    it 'raises when User.all is not enumerable' do
      allow(User).to receive(:all).and_return(nil)
      expect do
        generator.process_all_users
      end.to raise_error(NoMethodError)
    end
  end
end
