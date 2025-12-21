require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) { described_class.new }

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    context 'with valid user_ids' do
      let(:posts1) { double('Posts', count: 2) }
      let(:posts2) { double('Posts', count: 0) }
      let(:user1) { double('User', id: 1, name: 'Alice', posts: posts1) }
      let(:user2) { double('User', id: 2, name: 'Bob', posts: posts2) }

      before do
        allow(User).to receive(:find) do |id|
          if id == 1
            user1
          elsif id == 2
            user2
          else
            raise StandardError, 'not found'
          end
        end
      end

      it 'prints each user name and post count' do
        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 2 posts\nBob: 0 posts\n").to_stdout
      end

      it 'queries for each provided user id' do
        expect(User).to receive(:find).with(1).once.and_return(user1)
        expect(User).to receive(:find).with(2).once.and_return(user2)
        expect do
          generator.generate_user_report([1, 2])
        end.to output.to_stdout
      end
    end

    context 'with empty user_ids' do
      it 'does not query and produces no output' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a user id is not found' do
      before do
        allow(User).to receive(:find).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([999])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when nil is passed' do
      it 'raises an error' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    it 'returns CSV string for given records' do
      records = [
        double('Record', id: 1, name: 'Alice'),
        double('Record', id: 2, name: 'Bob')
      ]
      result = generator.build_csv(records)
      expect(result).to eq("1,Alice\n2,Bob\n")
    end

    it 'handles nil fields gracefully' do
      records = [
        double('Record', id: 1, name: nil)
      ]
      result = generator.build_csv(records)
      expect(result).to eq("1,\n")
    end

    it 'returns empty string for empty records' do
      result = generator.build_csv([])
      expect(result).to eq('')
    end

    it 'raises error when records is nil' do
      expect do
        generator.build_csv(nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#find_matches' do
    it 'returns matches that exist in both lists' do
      list_a = [1, 2, 3]
      list_b = [2, 3, 5]
      result = generator.find_matches(list_a, list_b)
      expect(result).to eq([2, 3])
    end

    it 'includes duplicates when list_b has duplicate matching items' do
      list_a = [2]
      list_b = [1, 2, 2, 3]
      result = generator.find_matches(list_a, list_b)
      expect(result).to eq([2, 2])
    end

    it 'returns empty array when either list is empty' do
      expect(generator.find_matches([], [1, 2])).to eq([])
      expect(generator.find_matches([1, 2], [])).to eq([])
      expect(generator.find_matches([], [])).to eq([])
    end

    it 'raises error when list_a is nil' do
      expect do
        generator.find_matches(nil, [1, 2])
      end.to raise_error(NoMethodError)
    end

    it 'raises error when list_b is nil' do
      expect do
        generator.find_matches([1, 2], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', Class.new)
    end

    it 'sends an email to each user returned by User.all' do
      u1 = double('User')
      u2 = double('User')
      allow(User).to receive(:all).and_return([u1, u2])
      expect(generator).to receive(:send_email).with(u1).once
      expect(generator).to receive(:send_email).with(u2).once
      generator.process_all_users
    end

    it 'does nothing when there are no users' do
      allow(User).to receive(:all).and_return([])
      expect(generator).not_to receive(:send_email)
      generator.process_all_users
    end

    it 'propagates errors from send_email' do
      u1 = double('User')
      allow(User).to receive(:all).and_return([u1])
      expect(generator).to receive(:send_email).with(u1).and_raise('boom')
      expect do
        generator.process_all_users
      end.to raise_error('boom')
    end
  end
end
