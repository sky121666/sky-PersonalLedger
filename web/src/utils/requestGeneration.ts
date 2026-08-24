export function createRequestGeneration() {
  let latestGeneration = 0

  return {
    begin() {
      latestGeneration += 1
      return latestGeneration
    },
    isLatest(generation: number) {
      return generation === latestGeneration
    },
  }
}
