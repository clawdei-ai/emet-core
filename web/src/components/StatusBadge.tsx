import { STATUS_LABELS, STATUS_COLORS } from '../lib/format';

export function StatusBadge({ status }: { status: number }) {
  return (
    <span
      className="status-badge"
      style={{ backgroundColor: STATUS_COLORS[status] + '20', color: STATUS_COLORS[status], borderColor: STATUS_COLORS[status] }}
    >
      {STATUS_LABELS[status]}
    </span>
  );
}
