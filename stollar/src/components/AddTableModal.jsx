import { useState } from 'react'

export default function AddTableModal({ room, onClose, onAdd }) {
  const nextNum = (room.tables.reduce((m, t) => Math.max(m, t.number || 0), 0) + 1)
  const [number, setNumber] = useState(String(nextNum))
  const [name, setName] = useState('')
  const [capacity, setCapacity] = useState('4')
  const [status, setStatus] = useState('available')

  function handleSubmit(e) {
    e.preventDefault()
    onAdd({
      number: parseInt(number) || nextNum,
      name: name.trim(),
      capacity: parseInt(capacity) || 4,
      status,
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-[#1e293b] rounded-2xl p-6 w-80 shadow-2xl border border-slate-700">
        <div className="flex items-center gap-2 mb-5">
          <div className="w-2.5 h-2.5 rounded-full" style={{ background: room.color }} />
          <h2 className="text-white font-bold text-lg">Stol qo'shish</h2>
          <span className="text-slate-500 text-sm">— {room.name}</span>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-slate-400 text-xs mb-1.5 block">Raqam *</label>
              <input
                autoFocus
                type="number"
                min="1"
                value={number}
                onChange={e => setNumber(e.target.value)}
                className="w-full bg-[#0f172a] text-white border border-slate-600 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#22c55e] transition-colors"
              />
            </div>
            <div>
              <label className="text-slate-400 text-xs mb-1.5 block">Sig'imi</label>
              <input
                type="number"
                min="1"
                max="20"
                value={capacity}
                onChange={e => setCapacity(e.target.value)}
                className="w-full bg-[#0f172a] text-white border border-slate-600 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#22c55e] transition-colors"
              />
            </div>
          </div>

          <div>
            <label className="text-slate-400 text-xs mb-1.5 block">Nomi (ixtiyoriy)</label>
            <input
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="Masalan: VIP stol"
              className="w-full bg-[#0f172a] text-white border border-slate-600 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#22c55e] transition-colors placeholder-slate-600"
            />
          </div>

          <div>
            <label className="text-slate-400 text-xs mb-2 block">Holati</label>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setStatus('available')}
                className={`flex-1 py-2 rounded-xl text-sm font-medium border transition-all ${
                  status === 'available'
                    ? 'bg-[#22c55e]/20 border-[#22c55e] text-[#22c55e]'
                    : 'border-slate-600 text-slate-400 hover:border-slate-500'
                }`}
              >
                ● Bo'sh
              </button>
              <button
                type="button"
                onClick={() => setStatus('occupied')}
                className={`flex-1 py-2 rounded-xl text-sm font-medium border transition-all ${
                  status === 'occupied'
                    ? 'bg-[#ef4444]/20 border-[#ef4444] text-[#ef4444]'
                    : 'border-slate-600 text-slate-400 hover:border-slate-500'
                }`}
              >
                ● Band
              </button>
            </div>
          </div>

          <div className="flex gap-2 mt-1">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 py-2.5 bg-[#334155] hover:bg-[#475569] text-slate-300 rounded-xl text-sm font-medium transition-colors"
            >
              Bekor
            </button>
            <button
              type="submit"
              className="flex-1 py-2.5 bg-[#22c55e] hover:bg-green-400 text-white rounded-xl text-sm font-medium transition-colors"
            >
              Qo'shish
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
