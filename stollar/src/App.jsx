import { useState, useEffect } from 'react'
import Sidebar from './components/Sidebar'
import RoomCanvas from './components/RoomCanvas'
import AddRoomModal from './components/AddRoomModal'
import AddTableModal from './components/AddTableModal'
import EditTableModal from './components/EditTableModal'

const STORAGE_KEY = 'sultan_stollar_v1'

function genId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2)
}

function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? JSON.parse(raw) : []
  } catch {
    return []
  }
}

export default function App() {
  const [rooms, setRooms] = useState(load)
  const [activeRoomId, setActiveRoomId] = useState(() => {
    const r = load()
    return r.length > 0 ? r[0].id : null
  })
  const [showAddRoom, setShowAddRoom] = useState(false)
  const [showAddTable, setShowAddTable] = useState(false)
  const [editingTable, setEditingTable] = useState(null)
  const [editingRoom, setEditingRoom] = useState(null)

  // Persist to localStorage
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(rooms))
  }, [rooms])

  // Auto-select first room
  useEffect(() => {
    if (!activeRoomId && rooms.length > 0) setActiveRoomId(rooms[0].id)
    if (activeRoomId && !rooms.find(r => r.id === activeRoomId)) {
      setActiveRoomId(rooms.length > 0 ? rooms[0].id : null)
    }
  }, [rooms, activeRoomId])

  const activeRoom = rooms.find(r => r.id === activeRoomId) ?? null

  // ── Room CRUD ─────────────────────────────────────────────────────────────
  function addRoom({ name, color }) {
    const room = { id: genId(), name, color, tables: [] }
    setRooms(prev => [...prev, room])
    setActiveRoomId(room.id)
  }

  function updateRoom(roomId, updates) {
    setRooms(prev => prev.map(r => r.id === roomId ? { ...r, ...updates } : r))
  }

  function deleteRoom(roomId) {
    setRooms(prev => prev.filter(r => r.id !== roomId))
  }

  // ── Table CRUD ────────────────────────────────────────────────────────────
  function addTable(data) {
    if (!activeRoomId) return
    const table = {
      id: genId(),
      number: data.number,
      name: data.name,
      capacity: data.capacity,
      status: data.status || 'available',
      x: 80 + Math.random() * 300,
      y: 80 + Math.random() * 200,
    }
    setRooms(prev => prev.map(r =>
      r.id === activeRoomId ? { ...r, tables: [...r.tables, table] } : r
    ))
  }

  function updateTable(tableId, updates) {
    setRooms(prev => prev.map(r =>
      r.id === activeRoomId
        ? { ...r, tables: r.tables.map(t => t.id === tableId ? { ...t, ...updates } : t) }
        : r
    ))
  }

  function deleteTable(tableId) {
    setRooms(prev => prev.map(r =>
      r.id === activeRoomId
        ? { ...r, tables: r.tables.filter(t => t.id !== tableId) }
        : r
    ))
  }

  function moveTable(tableId, x, y) {
    setRooms(prev => prev.map(r =>
      r.id === activeRoomId
        ? { ...r, tables: r.tables.map(t => t.id === tableId ? { ...t, x, y } : t) }
        : r
    ))
  }

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-[#0f172a]">
      <Sidebar
        rooms={rooms}
        activeRoomId={activeRoomId}
        onSelectRoom={setActiveRoomId}
        onAddRoom={() => setShowAddRoom(true)}
        onAddTable={() => activeRoomId && setShowAddTable(true)}
        onEditRoom={setEditingRoom}
        onDeleteRoom={deleteRoom}
        hasActiveRoom={!!activeRoomId}
      />

      <main className="flex-1 relative overflow-hidden">
        {activeRoom ? (
          <RoomCanvas
            room={activeRoom}
            onMoveTable={moveTable}
            onClickTable={setEditingTable}
          />
        ) : (
          <div className="flex flex-col items-center justify-center h-full gap-6 text-slate-500">
            <svg className="w-24 h-24 opacity-20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1">
              <rect x="3" y="3" width="18" height="18" rx="2"/>
              <path d="M9 9h6v6H9z"/>
            </svg>
            <div className="text-center">
              <p className="text-xl text-slate-400 font-medium">Hona tanlanmagan</p>
              <p className="text-sm mt-1">Chap paneldan hona tanlang yoki yangi hona yarating</p>
            </div>
            <button
              onClick={() => setShowAddRoom(true)}
              className="px-6 py-3 bg-[#22c55e] hover:bg-green-400 text-white rounded-xl font-semibold transition-colors flex items-center gap-2"
            >
              <span className="text-lg">+</span> Hona qo'shish
            </button>
          </div>
        )}
      </main>

      {showAddRoom && (
        <AddRoomModal
          onClose={() => setShowAddRoom(false)}
          onAdd={(data) => { addRoom(data); setShowAddRoom(false) }}
        />
      )}

      {editingRoom && (
        <AddRoomModal
          initial={editingRoom}
          onClose={() => setEditingRoom(null)}
          onAdd={(data) => { updateRoom(editingRoom.id, data); setEditingRoom(null) }}
        />
      )}

      {showAddTable && activeRoom && (
        <AddTableModal
          room={activeRoom}
          onClose={() => setShowAddTable(false)}
          onAdd={(data) => { addTable(data); setShowAddTable(false) }}
        />
      )}

      {editingTable && (
        <EditTableModal
          table={editingTable}
          onClose={() => setEditingTable(null)}
          onUpdate={(updates) => { updateTable(editingTable.id, updates); setEditingTable(null) }}
          onDelete={() => { deleteTable(editingTable.id); setEditingTable(null) }}
        />
      )}
    </div>
  )
}
