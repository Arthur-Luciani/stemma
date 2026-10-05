import styles from './App.module.css';

export function App() {
  return (
    <main className={styles.page}>
      <div className={styles.icon} aria-hidden="true">
        <span className={styles.vocals} />
        <span className={styles.drums} />
        <span className={styles.bass} />
        <span className={styles.other} />
      </div>
      <h1 className={styles.wordmark}>stemma</h1>
      <p className={styles.note}>Em construção.</p>
    </main>
  );
}
