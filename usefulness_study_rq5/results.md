| Project | Relaxed Oca | Daikon |
|---|---|---|
| Cli | 0/5 | 0/5 |
| Codec | 2/5 | 0/4 |
| Collections | 5/5 | 1/5 |
| Gson | 0/5 | 0/5 |
| JxPath | 1/5 | 0/4 |
| Math | 1/5 | 2/5 |
| **Total** | **9/30** | **3/28** |

# Relaxed Oca hits

## Codec

### Codec_17
- ENTRY `StringUtils#newStringIso8859_1(byte[])`: `bytes != null && bytes.length >= 0`

### Codec_18
- EXIT `StringUtils#equals(CharSequence,CharSequence)`: `(cs1 == cs2) == result`
- EXIT `StringUtils#equals(CharSequence,CharSequence)`: `result == (cs1 == null ? cs2 == null : cs1.equals(cs2))`

## Collections

### Collections_24
- ENTRY `AbstractMapBag#addAll(Collection)`: `coll != null`
- ENTRY `AbstractMapBag#addAll(Collection)`: `coll.iterator() != null`
- ENTRY `AbstractMapBag#addAll(Collection)`: `coll.size() >= 0`

### Collections_25
- ENTRY `Inverse#getKey(Object)`: `value == null || TreeBidiMap.this.containsValue(value)`
- ENTRY `TreeBidiMap#getKey(Object)`: `value == null || TreeBidiMap.this.containsValue(value)`
- ENTRY `TreeBidiMap#getKey(Object)`: `value == null || TreeBidiMap.this.valuesSet.contains(value)`
- ENTRY `LazyIteratorChain#hasNext()`: `chainExhausted == true || currentIterator != null`
- ENTRY `LazyIteratorChain#updateCurrentIterator()`: `chainExhausted == (nextIterator(callCounter + 1) == null)`
- ENTRY `LazyIteratorChain#updateCurrentIterator()`: `chainExhausted || currentIterator != null`
- ENTRY `LazyIteratorChain#updateCurrentIterator()`: `currentIterator == null || currentIterator.hasNext() || chainExhausted`
- ENTRY `TreeList#iterator()`: `toArray().length == size()`
- EXIT `Inverse#getKey(Object)`: `result == null || TreeBidiMap.this.containsValue(value)`
- EXIT `Inverse#inverseBidiMap()`: `result.containsValue((K) null) == false`
- EXIT `TreeBidiMap#doRemoveKey(Object)`: `(result == null) == (key == null || lookupKey(key) == null)`
- EXIT `TreeBidiMap#getKey(Object)`: `value == null || (result != null && this.get(result).equals(value))`
- EXIT `LazyIteratorChain#updateCurrentIterator()`: `chainExhausted == (nextIterator(callCounter + 1) == null) || !currentIterator.hasNext()`
- EXIT `LazyIteratorChain#updateCurrentIterator()`: `lastUsedIterator == currentIterator`

### Collections_26
- ENTRY `PassiveExpiringMap#removeIfExpired(Object,long)`: `isExpired(now, expirationMap.get(key)) == (expirationMap.get(key) != null && expirationMap.get(key) >= 0 && expirationMap.get(key) < now)`
- EXIT `AVLNode#indexOf(Object,int)`: `result == -1 || result >= index`
- EXIT `AVLNode#rotateLeft()`: `result == this.right`
- EXIT `TreeList#indexOf(Object,int)`: `(result == -1) || (result >= 0 && result >= index)`
- EXIT `TreeList#indexOf(Object,int)`: `result == -1 || index <= result`
- EXIT `TreeList#recalcHeight()`: `!(getLeftSubTree() != null && getRightSubTree() != null && Math.abs(getLeftSubTree().height - getRightSubTree().height) > 1)`
- EXIT `TreeList#rotateLeft()`: `result == this.right`

### Collections_27
- ENTRY `IterableUtils#chainedIterable(Iterable,Iterable)`: `!(a instanceof Collection) || !(b instanceof Collection) || !((Collection<?>)a).isEmpty() || !((Collection<?>)b).isEmpty()`
- ENTRY `IterableUtils#forEach(Iterable,Closure)`: `!(iterable == null) || iterable instanceof Iterable`
- ENTRY `MultiKeyMap#get(Object,Object,Object)`: `!(key1 == null && key2 == null && key3 == null)`
- ENTRY `MultiKeyMap#get(Object,Object,Object,Object)`: `key1 != key2 || key2 != key3 || key3 != key4 || key4 != key1`
- ENTRY `MultiKeyMap#get(Object,Object,Object,Object,Object)`: `key1 != null`
- ENTRY `MultiKeyMap#get(Object,Object,Object,Object,Object)`: `key2 != null`
- EXIT `IterableUtils#chainedIterable(Iterable,Iterable)`: `!IterableUtils.isEmpty(result)`
- EXIT `TreeBidiMap#put(K,V)`: `result == null || containsValue(result)`
- EXIT `TreeBidiMap#put(K,V)`: `result == null || result.equals(get(key))`
- EXIT `LazyIteratorChain#next()`: `result != null`
- EXIT `MultiKeyMap#get(Object,Object,Object,Object)`: `result == null || isEqualKey(decorated().data[decorated().hashIndex(hash(key1, key2, key3, key4), decorated().data.length)], key1, key2, key3, key4)`

### Collections_28
- ENTRY `AVLNode#setValue(E)`: `this.value != null || obj == null`
- ENTRY `TreeList#set(int,E)`: `index < size()`
- ENTRY `TreeList#set(int,E)`: `index >= 0`
- ENTRY `TreeList#set(int,E)`: `root != null`

## JxPath

### JxPath_22
- ENTRY `NamespacePointer#getNamespaceURI()`: `namespaceURI == null || !namespaceURI.isEmpty()`
- EXIT `NamespacePointer#getNamespaceURI()`: `result == null || !result.trim().isEmpty()`
- EXIT `NamespacePointer#getNamespaceURI()`: `result == null || result.equals(parent.getNamespaceURI(prefix))`
- EXIT `NamespacePointer#getNamespaceURI()`: `result == null || result.length() > 0`

## Math

### Math_105
- ENTRY `SimpleRegression#getSumSquaredErrors()`: `Double.isNaN(getSumSquaredErrors()) || getSumSquaredErrors() >= 0`

# Daikon hits

## Collections

### Collections_24
- ENTER `UnmodifiableBoundedCollection(BoundedCollection)`: `coll.getClass().getName() == FixedSizeList.class`
- OBJECT `UnmodifiableBoundedCollection`: `this.collection.getClass().getName() == FixedSizeList.class`

## Math

### Math_102
- EXIT `ChiSquareTestImpl.chiSquare(double[], long[])`: `expected[] elements > return`

### Math_105
- EXIT `SimpleRegression.getSumSquaredErrors()`: `return >= 0.0`
