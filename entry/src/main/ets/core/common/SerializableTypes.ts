export type Ctor<T> = new (...args: any[]) => T;
export type AbstractCtor<T> = abstract new (...args: any[]) => T;

export function extendsBase<Base, Derived>(
    base: AbstractCtor<Base>,
    ctor: AbstractCtor<Derived>
): ctor is AbstractCtor<Derived & Base> {
    return (ctor as Function) === (base as Function) ||
        base.prototype.isPrototypeOf(ctor.prototype);
}
