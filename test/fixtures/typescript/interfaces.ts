interface User {
  id: number;
  name: string;
  email?: string;
}

type ID = string | number;

function getUser(id: ID): User {
  return { id: 1, name: "Alice" };
}
