import { useState } from 'react'

const ROOM_COLORS = [
  '#22c55e','#3b82f6','#a855f7','#f59e0b',
  '#ef4444','#ec4899','#06b6d4','#84cc16',
]

export default function Sidebar({
  rooms, activeRoomId, onSelectRoom,
  onAddRoom, onAddTable,
  onEditRoom, onDeleteRoom,
  hasActiveRoom,
}) {
  const [hoveredRoom, setHoveredRoom] = useState(null)

  const totalTables = rooms.reduce((s, r) => s + r.tables.length, 0)
  const occupiedTotal = rooms.reduce(
    (s, r) => s + r.tables.filter(t => t.status === 'occupied').length, 0
  )

  return (
    <aside className="w-64 flex flex-col h-screen bg-[#1e293b] border-r border-slate-700 shrink-0">
      {/* Header */}
      <div className="px-4 py-5 border-b border-slate-700">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-8 h-8 bg-[#22c55e] rounded-lg flex items-center justify-center">
            <svg viewBox="0 0 24 24" className="w-5 h-5 fill-white">
              <rect x="3" y="11" width="18" height="2" rx="1"/>
              <rect x="6" y="7" width="12" height="2" rx="1"/>
              <rect x="6" y="15" width="2" height="5" rx="1"/>
              <rect x="16" y="15" width="2" height="5" rx="1"/>
            </svg>
          </div>
          <div>
            <h1 className="text-white font-bold text-base leading-none">Stollar</h1>
            <p className="text-slate-400 text-xs mt-0.5">Boshqaruv paneli</p>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-2 gap-2">
          <div className="bg-[#0f172a] rounded-lg px-3 py-2">
            <div className="text-[#22c55e] text-lg font-bold leading-none">
              {totalTables - occupiedTotal}
            </div>
            <div className="text-slate-400 text-xs mt-0.5">Bo'sh</div>
          </div>
          <div className="bg-[#0f172a] rounded-lg px-3 py-2">
            <div className="text-[#ef4444] text-lg font-bold leading-none">
              {occupiedTotal}
            </div>
            <div className="text-slate-400 text-xs mt-0.5">Band</div>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="px-4 py-3 flex gap-2">
        <button
          onClick={onAddRoom}
          className="flex-1 py-2 bg-[#334155] hover:bg-[#475569] text-white text-xs font-medium rounded-lg transition-colors flex items-center justify-center gap-1"
        >
          <span className="text-base leading-none">+</span> Hona
        </button>
        <button
          onClick={onAddTable}
          disabled={!hasActiveRoom}
          className={`flex-1 py-2 text-xs font-medium rounded-lg transition-colors flex items-center justify-center gap-1
            ${hasActiveRoom
              ? 'bg-[#22c55e] hover:bg-green-400 text-white'
              : 'bg-[#334155] text-slate-500 cursor-not-allowed'}`}
        >
          <span className="text-base leading-none">+</span> Stol
        </button>
      </div>

      {/* Room list */}
      <div className="flex-1 overflow-y-auto px-3 pb-4">
        <p className="text-slate-500 text-xs px-1 pb-2 uppercase tracking-wider">
          Honalar ({rooms.length})
        </p>

        {rooms.length === 0 && (
          <div className="text-center py-8 text-slate-600 text-sm">
            Hona yo'q
          </div>
        )}

        {rooms.map(room => {
          const isActive = room.id === activeRoomId
          const occupied = room.tables.filter(t => t.status === 'occupied').length
          const free = room.tables.length - occupied

          return (
            <div
              key={room.id}
              onMouseEnter={() => setHoveredRoom(room.id)}
              onMouseLeave={() => setHoveredRoom(null)}
              className={`mb-1 rounded-xl transition-all cursor-pointer group
                ${isActive
                  ? 'bg-[#0f172a] ring-1 ring-slate-600'
                  : 'hover:bg-[#0f172a]'}`}
            >
              <div
                className="flex items-center gap-3 px-3 py-3"
                onClick={() => onSelectRoom(room.id)}
              >
                {/* Color dot */}
                <div
                  className="w-3 h-3 rounded-full shrink-0"
                  style={{ background: room.color }}
                />
                <div className="flex-1 min-w-0">
                  <div className="text-white text-sm font-medium truncate">{room.name}</div>
                  <div className="flex gap-2 mt-0.5">
                    <span className="text-[#22c55e] text-xs">{free} bo'sh</span>
                    {occupied > 0 && <span className="text-[#ef4444] text-xs">{occupied} band</span>}
                  </div>
                </div>
                {/* Table count badge */}
                <span className="text-slate-500 text-xs bg-[#334155] px-2 py-0.5 rounded-full shrink-0">
                  {room.tables.length}
                </span>
              </div>

              {/* Room actions (shown on hover or active) */}
              {(hoveredRoom === room.id || isActive) && (
                <div className="flex gap-1 px-3 pb-2">
                  <button
                    onClick={(e) => { e.stopPropagation(); onEditRoom(room) }}
                    className="flex-1 py-1 text-xs text-slate-400 hover:text-white bg-[#334155] hover:bg-[#475569] rounded-lg transition-colors"
                  >
                    Tahrirlash
                  </button>
                  <button
                    onClick={(e) => {
                      e.stopPropagation()
                      if (confirm(`"${room.name}" honasini o'chirasizmi? (${room.tables.length} stol)`)) {
                        onDeleteRoom(room.id)
                      }
                    }}
                    className="py-1 px-2 text-xs text-red-400 hover:text-white hover:bg-red-500 rounded-lg transition-colors"
                  >
                    ✕
                  </button>
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Footer */}
      <div className="px-4 py-3 border-t border-slate-700 text-center">
        <p className="text-slate-600 text-xs">Sultan Restoran v1.1</p>
      </div>
    </aside>
  )
}
