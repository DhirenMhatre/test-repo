require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) { described_class.new }

  before do
    stub_const('User', Class.new)
  end

  describe '#generate_user_report' do
    context 'with valid user ids' do
      let(:posts1) { double('Posts', count: 2) }
      let(:posts2) { double('Posts', count: 3) }
      let(:user1) { instance_double('User', name: 'Alice', posts: posts1) }
      let(:user2) { instance_double('User', name: 'Bob', posts: posts2) }

      before do
        allow(User).to receive(:find) do |id|
          if id == 1
            user1
          elsif id == 2
            user2
          else
            raise 'not found'
          end
        end
      end

      it 'prints a line per user with post counts' do
        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
      end
    end

    context 'with an empty array' do
      it 'does nothing and prints nothing' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a lookup fails' do
      let(:posts1) { double('Posts', count: 2) }
      let(:user1) { instance_double('User', name: 'Alice', posts: posts1) }

      before do
        allow(User).to receive(:find) do |id|
          raise StandardError, "boom for #{id}" unless id == 1

          user1
        end
      end

      it 'raises the underlying error' do
        expect do
          generator.generate_user_report([1, 99])
        end.to raise_error(StandardError, /boom/)
      end
    end
  end

  describe '#build_csv' do
    Record = Struct.new(:id, :name)

    context 'with multiple records' do
      let(:records) do
        [
          Record.new(1, 'Alice'),
          Record.new(2, 'Bob')
        ]
      end

      it 'returns a CSV-like string with one line per record' do
        result = generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
        expect(result).to be_a(String)
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'with a record missing required attributes' do
      let(:bad_record) { Object.new }

      it 'raises NoMethodError for missing id/name' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end

    context 'with nil attribute values' do
      let(:records) do
        [
          Record.new(nil, 'Alice'),
          Record.new(2, nil)
        ]
      end

      it 'coerces nils to empty strings in the output' do
        expect(generator.build_csv(records)).to eq(",Alice\n2,\n")
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping arrays including duplicates' do
      let(:list_a) { [1, 2, 2, 3] }
      let(:list_b) { [2, 3, 3] }

      it 'returns all matches accounting for multiplicity in list_b' do
        expect(generator.find_matches(list_a, list_b)).to eq([2, 2, 3, 3])
      end
    end

    context 'with no overlap' do
      let(:list_a) { [1, 4] }
      let(:list_b) { [2, 3] }

      it 'returns an empty array' do
        expect(generator.find_matches(list_a, list_b)).to eq([])
      end
    end

    context 'with empty inputs' do
      it 'returns empty array when list_a is empty' do
        expect(generator.find_matches([], [1, 2])).to eq([])
      end

      it 'returns empty array when list_b is empty' do
        expect(generator.find_matches([1, 2], [])).to eq([])
      end
    end

    context 'with nil lists' do
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
    let(:user1) { instance_double('User', id: 1) }
    let(:user2) { instance_double('User', id: 2) }

    context 'when there are users' do
      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'sends an email to each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user1).once
        expect(generator).to have_received(:send_email).with(user2).once
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not send any emails' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending an email fails' do
      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email) do |user|
          raise 'delivery failed' if user == user2
        end
      end

      it 'raises the error and stops processing' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, /delivery failed/)
      end

      it 'attempts to send to earlier users before failing' do
        begin
          generator.process_all_users
        rescue RuntimeError
        end
        expect(generator).to have_received(:send_email).with(user1)
      end
    end
  end
end
