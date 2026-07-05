import { useState } from 'react'

export default function EditTableModal({ table, onClose, onUpdate, onDelete }) {
  const [number, setNumber] = useState(String(table.number))
  const [name, setName] = useState(table.name || '')
  const [capacity, setCapacity] = useState(String(table.capacity || 4))
  const [status, setStatus] = useState(table.status)
  const [confirmDelete, setConfirmDelete] = useState(false)

  function handleSubmit(e) {
    e.preventDefault()
    onUpdate({
      number: parseInt(number) || table.number,
      name: name.trim(),
      capacity: parseInt(capacity) || 4,
      status,
    })
  }

  if (confirmDelete) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center">
        <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
        <div className="relative bg-[#1e293b] rounded-2xl p-6 w-72 shadow-2xl border border-red-800">
          <h2 className="text-white font-bold text-base mb-2">Stolni o'chirish</h2>
          <p className="text-slate-400 text-sm mb-5">
            <strong className="text-white">Stol {table.number}</strong>ni o'chirasizmi?
            Bu amalni qaytarib bo'lmaydi.
          </p>
          <div className="flex gap-2">
            <button
              onClick={() => setConfirmDelete(false)}
              className="flex-1 py-2.5 bg-[#334155] hover:bg-[#475569] text-slate-300 rounded-xl text-sm font-medium transition-colors"
            >
              Bekor
            </button>
            <button
              onClick={onDelete}
              className="flex-1 py-2.5 bg-red-600 hover:bg-red-500 text-white rounded-xl text-sm font-medium transition-colors"
            >
              O'chirish
            </button>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-[#1e293b] rounded-2xl p-6 w-80 shadow-2xl border border-slate-700">
        <div className="flex items-center justify-between mb-5">
          <h2 className="text-white font-bold text-lg">Stol {table.number}</h2>
          <button
            onClick={() => setConfirmDelete(true)}
            className="py-1 px-3 text-xs text-red-400 hover:bg-red-500/20 rounded-lg border border-red-800 hover:border-red-500 transition-colors"
          >
            O'chirish
          </button>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-slate-400 text-xs mb-1.5 block">Raqam</label>
              <input
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
            <label className="text-slate-400 text-xs mb-1.5 block">Nomi</label>
            <input
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="VIP stol, Ko'cha..."
              className="w-full bg-[#0f172a] text-white border border-slate-600 rounded-xl px-3 py-2.5 text-sm outline-none focus:border-[#22c55e] transition-colors placeholder-slate-600"
            />
          </div>

          {/* Status toggle */}
          <div>
            <label className="text-slate-400 text-xs mb-2 block">Holat</label>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setStatus('available')}
                className={`flex-1 py-2.5 rounded-xl text-sm font-medium border transition-all ${
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
                className={`flex-1 py-2.5 rounded-xl text-sm font-medium border transition-all ${
                  status === 'occupied'
                    ? 'bg-[#ef4444]/20 border-[#ef4444] text-[#ef4444]'
                    : 'border-slate-600 text-slate-400 hover:border-slate-500'
                }`}
              >
                ● Band
              </button>
            </div>
          </div>

          {/* Position info */}
          <div className="bg-[#0f172a] rounded-xl px-3 py-2 text-xs text-slate-500 flex gap-3">
            <span>X: {Math.round(table.x)}</span>
            <span>Y: {Math.round(table.y)}</span>
            <span className="ml-auto">Sudrab joyini o'zgartiring</span>
          </div>

          <div className="flex gap-2">
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
              Saqlash
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
