require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) { 'Alice' }
      let(:user) do
        described_class.new(name)
      end

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }
      let(:user) do
        described_class.new(name)
      end

      it 'does not raise and sets @name to nil' do
        expect do
          described_class.new(name)
        end.not_to raise_error
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:name) { '' }
      let(:user) do
        described_class.new(name)
      end

      it 'stores the empty string as @name' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:name) { 'Tester' }
    let(:user) do
      described_class.new(name)
    end

    let(:db) do
      double('DB')
    end

    before do
      stub_const('DB', db)
    end

    context 'when given an integer id' do
      let(:id) { 42 }
      let(:rows) do
        [{ id: 42, name: 'Ann' }]
      end

      it 'executes the expected SQL and returns DB results' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return(rows)
        result = user.find_user(id)
        expect(result).to eq(rows)
      end
    end

    context 'when given a string id that could be unsafe' do
      let(:id) { '1 OR 1=1' }
      let(:rows) do
        []
      end

      it 'interpolates the id directly into the SQL string' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 1 OR 1=1').and_return(rows)
        result = user.find_user(id)
        expect(result).to eq(rows)
      end
    end

    context 'when given nil id' do
      let(:id) { nil }

      it 'calls DB with a SQL missing the id value and returns nil from DB' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(nil)
        result = user.find_user(id)
        expect(result).to be_nil
      end
    end

    context 'when DB raises an error' do
      let(:id) { -5 }

      it 'propagates the error' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = -5').and_raise(StandardError, 'boom')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'boom')
      end
    end
  end

  describe '#bad_method' do
    let(:name) { 'Bob' }
    let(:user) do
      described_class.new(name)
    end

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not depend on the instance @name' do
      other = described_class.new(nil)
      expect(other.bad_method).to eq(6)
    end
  end
end
