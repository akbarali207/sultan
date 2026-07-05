import { useRef, useCallback } from 'react'
import Draggable from 'react-draggable'

function TableCard({ table }) {
  const isOccupied = table.status === 'occupied'
  const color = isOccupied ? '#ef4444' : '#22c55e'

  return (
    <div
      style={{ borderColor: color }}
      className="w-20 h-20 rounded-2xl border-2 bg-[#1e293b] flex flex-col items-center justify-center gap-1 select-none shadow-lg hover:shadow-xl transition-shadow"
    >
      {/* Chair icon on top */}
      <svg viewBox="0 0 24 24" className="w-6 h-6" fill="none" stroke={color} strokeWidth="2">
        <path d="M6 2h12M6 7h12M4 7v10M20 7v10M4 17h16"/>
        <path d="M7 17v3M17 17v3"/>
      </svg>

      {/* Table number */}
      <span className="text-white font-bold text-sm leading-none">
        {table.number}
      </span>

      {/* Status dot */}
      <div
        className="w-2 h-2 rounded-full"
        style={{ background: color }}
      />
    </div>
  )
}

export default function RoomCanvas({ room, onMoveTable, onClickTable }) {
  const canvasRef = useRef(null)
  // Track whether a drag occurred to suppress click
  const draggedRef = useRef(false)

  const handleStop = useCallback((tableId, e, data) => {
    onMoveTable(tableId, data.x, data.y)
    // Short delay so the click handler can check this flag
    setTimeout(() => { draggedRef.current = false }, 50)
  }, [onMoveTable])

  const handleDrag = useCallback(() => {
    draggedRef.current = true
  }, [])

  const handleClick = useCallback((table) => {
    if (!draggedRef.current) onClickTable(table)
  }, [onClickTable])

  const occupied = room.tables.filter(t => t.status === 'occupied').length
  const free = room.tables.length - occupied

  return (
    <div className="relative w-full h-full flex flex-col">
      {/* Room header bar */}
      <div className="flex items-center gap-4 px-5 py-3 bg-[#1e293b] border-b border-slate-700 shrink-0 z-10">
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full" style={{ background: room.color }} />
          <h2 className="text-white font-bold text-lg">{room.name}</h2>
        </div>
        <div className="flex gap-3 ml-2">
          <span className="flex items-center gap-1.5 text-sm">
            <span className="w-2 h-2 rounded-full bg-[#22c55e] inline-block" />
            <span className="text-slate-300">{free} bo'sh</span>
          </span>
          <span className="flex items-center gap-1.5 text-sm">
            <span className="w-2 h-2 rounded-full bg-[#ef4444] inline-block" />
            <span className="text-slate-300">{occupied} band</span>
          </span>
          <span className="text-slate-500 text-sm">Jami: {room.tables.length}</span>
        </div>
        <div className="ml-auto text-slate-600 text-xs">
          Stolni sudrab joylashtiring
        </div>
      </div>

      {/* Canvas */}
      <div
        ref={canvasRef}
        className="canvas-grid relative flex-1 overflow-hidden"
      >
        {/* Empty state */}
        {room.tables.length === 0 && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 pointer-events-none">
            <svg className="w-16 h-16 text-slate-700" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1">
              <rect x="3" y="11" width="18" height="2" rx="1"/>
              <rect x="6" y="7" width="12" height="2" rx="1"/>
              <rect x="6" y="15" width="2" height="5" rx="1"/>
              <rect x="16" y="15" width="2" height="5" rx="1"/>
            </svg>
            <p className="text-slate-600 text-sm">Bu honada hali stollar yo'q</p>
            <p className="text-slate-700 text-xs">Chap paneldagi "+ Stol" tugmasini bosing</p>
          </div>
        )}

        {/* Draggable tables */}
        {room.tables.map(table => (
          <Draggable
            key={table.id}
            defaultPosition={{ x: table.x, y: table.y }}
            onDrag={handleDrag}
            onStop={(e, data) => handleStop(table.id, e, data)}
            bounds={canvasRef.current ? {
              left: 0,
              top: 0,
              right: (canvasRef.current.offsetWidth || 800) - 80,
              bottom: (canvasRef.current.offsetHeight || 600) - 80,
            } : 'parent'}
          >
            <div
              className="absolute cursor-grab active:cursor-grabbing"
              style={{ width: 80, height: 80 }}
              onClick={() => handleClick(table)}
            >
              <TableCard table={table} />
              {/* Name label below */}
              {table.name && (
                <div className="mt-1 text-center text-slate-400 text-xs leading-tight truncate w-20">
                  {table.name}
                </div>
              )}
            </div>
          </Draggable>
        ))}
      </div>
    </div>
  )
}
