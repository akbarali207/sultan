import { useState } from 'react'

const COLORS = [
  '#22c55e', '#3b82f6', '#a855f7', '#f59e0b',
  '#ef4444', '#ec4899', '#06b6d4', '#84cc16',
  '#f97316', '#8b5cf6', '#14b8a6', '#eab308',
]

export default function AddRoomModal({ onClose, onAdd, initial }) {
  const [name, setName] = useState(initial?.name ?? '')
  const [color, setColor] = useState(initial?.color ?? COLORS[0])

  function handleSubmit(e) {
    e.preventDefault()
    if (!name.trim()) return
    onAdd({ name: name.trim(), color })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-[#1e293b] rounded-2xl p-6 w-80 shadow-2xl border border-slate-700">
        <h2 className="text-white font-bold text-lg mb-5">
          {initial ? 'Honani tahrirlash' : "Yangi hona qo'shish"}
        </h2>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div>
            <label className="text-slate-400 text-xs mb-1.5 block">Hona nomi</label>
            <input
              autoFocus
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="Masalan: Asosiy zal"
              className="w-full bg-[#0f172a] text-white border border-slate-600 rounded-xl px-4 py-2.5 text-sm outline-none focus:border-[#22c55e] transition-colors placeholder-slate-600"
            />
          </div>

          <div>
            <label className="text-slate-400 text-xs mb-2 block">Rang</label>
            <div className="grid grid-cols-6 gap-2">
              {COLORS.map(c => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setColor(c)}
                  className={`w-8 h-8 rounded-lg transition-all ${
                    color === c ? 'ring-2 ring-white ring-offset-1 ring-offset-[#1e293b] scale-110' : 'hover:scale-105'
                  }`}
                  style={{ background: c }}
                />
              ))}
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
              disabled={!name.trim()}
              className="flex-1 py-2.5 bg-[#22c55e] hover:bg-green-400 disabled:opacity-40 disabled:cursor-not-allowed text-white rounded-xl text-sm font-medium transition-colors"
            >
              {initial ? 'Saqlash' : "Qo'shish"}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
