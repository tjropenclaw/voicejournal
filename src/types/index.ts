export interface JournalEntry {
  id: string;
  date: string; // ISO date string
  transcript: string;
  summary?: string;
  mood?: 'great' | 'good' | 'okay' | 'bad' | 'terrible';
  audioUrl?: string;
  createdAt: number;
  updatedAt: number;
}

export interface Habit {
  id: string;
  name: string;
  description?: string;
  frequency: 'daily' | 'weekly';
  color: string;
  icon?: string;
  createdAt: number;
}

export interface HabitLog {
  id: string;
  habitId: string;
  date: string; // ISO date string
  completed: boolean;
  note?: string;
}

export interface CallSession {
  id: string;
  status: 'idle' | 'connecting' | 'active' | 'ended';
  startedAt?: number;
  endedAt?: number;
  transcript?: string;
}
