require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:user_class) do
      Class.new
    end

    before do
      stub_const('User', user_class)
    end

    let(:user1) do
      double('user1', name: 'Alice')
    end

    let(:user2) do
      double('user2', name: 'Bob')
    end

    let(:user3) do
      double('user3', name: 'Carol')
    end

    let(:posts1) do
      double('posts1', count: 2)
    end

    let(:posts2) do
      double('posts2', count: 0)
    end

    let(:posts3) do
      double('posts3', count: 5)
    end

    before do
      allow(user1).to receive(:posts).and_return(posts1)
      allow(user2).to receive(:posts).and_return(posts2)
      allow(user3).to receive(:posts).and_return(posts3)
    end

    it 'queries each user id and prints their post counts' do
      expect(User).to receive(:find).with(1).and_return(user1)
      expect(User).to receive(:find).with(2).and_return(user2)
      expect(User).to receive(:find).with(3).and_return(user3)

      expect do
        generator.generate_user_report([1, 2, 3])
      end.to output("Alice: 2 posts\nBob: 0 posts\nCarol: 5 posts\n").to_stdout
    end

    context 'when user_ids is empty' do
      it 'does not query and prints nothing' do
        expect(User).not_to receive(:find)

        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a user lookup fails' do
      it 'raises the error and stops processing' do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'not found')

        expect do
          generator.generate_user_report([1, 2])
        end.to raise_error(StandardError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    it 'returns CSV lines for each record' do
      rec1 = double('record1')
      rec2 = double('record2')
      allow(rec1).to receive(:id).and_return(1)
      allow(rec1).to receive(:name).and_return('Alice')
      allow(rec2).to receive(:id).and_return(2)
      allow(rec2).to receive(:name).and_return('Bob')

      result = generator.build_csv([rec1, rec2])
      expect(result).to eq("1,Alice\n2,Bob\n")
    end

    it 'returns an empty string when records is empty' do
      result = generator.build_csv([])
      expect(result).to eq('')
    end

    it 'handles nil names by converting them to empty strings' do
      rec = double('record')
      allow(rec).to receive(:id).and_return(3)
      allow(rec).to receive(:name).and_return(nil)

      result = generator.build_csv([rec])
      expect(result).to eq("3,\n")
    end

    context 'with invalid input' do
      it 'raises an error when records is nil' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    it 'returns all items that appear in both lists preserving multiplicity' do
      list_a = [1, 2, 2, 3]
      list_b = [2, 2, 4]
      result = generator.find_matches(list_a, list_b)
      expect(result).to eq([2, 2, 2, 2])
    end

    it 'returns an empty array when no matches are found' do
      result = generator.find_matches([1, 3], [2, 4])
      expect(result).to eq([])
    end

    it 'returns an empty array when either list is empty' do
      expect(generator.find_matches([], [1, 2])).to eq([])
      expect(generator.find_matches([1, 2], [])).to eq([])
    end

    context 'with invalid input' do
      it 'raises an error when list_a is nil' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error when list_b is nil' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_class) do
      Class.new
    end

    before do
      stub_const('User', user_class)
    end

    it 'fetches all users and sends an email to each' do
      u1 = double('user1')
      u2 = double('user2')
      allow(User).to receive(:all).and_return([u1, u2])

      expect(generator).to receive(:send_email).with(u1)
      expect(generator).to receive(:send_email).with(u2)

      generator.process_all_users
    end

    it 'does nothing when there are no users' do
      allow(User).to receive(:all).and_return([])

      expect(generator).not_to receive(:send_email)

      generator.process_all_users
    end

    context 'when sending an email fails' do
      it 'propagates the error and stops processing remaining users' do
        u1 = double('user1')
        u2 = double('user2')
        allow(User).to receive(:all).and_return([u1, u2])

        allow(generator).to receive(:send_email).with(u1).and_raise(RuntimeError, 'smtp failure')
        expect(generator).not_to receive(:send_email).with(u2)

        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'smtp failure')
      end
    end
  end
end
